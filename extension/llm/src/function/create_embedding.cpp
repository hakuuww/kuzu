#include "common/assert.h"
#include "common/exception/connection.h"
#include "function/function.h"
#include "function/llm_functions.h"
#include "function/scalar_function.h"
#include "httplib.h"
#include "json.hpp"

using namespace kuzu::common;
using namespace kuzu::binder;
using namespace kuzu::function;
using namespace kuzu::catalog;
using namespace kuzu::processor;

namespace kuzu {
namespace llm_extension {

static void execFunc(const std::vector<std::shared_ptr<common::ValueVector>>& parameters,
    const std::vector<common::SelectionVector*>& /*parameterSelVectors*/,
    common::ValueVector& result, common::SelectionVector* resultSelVector, void* /*dataPtr*/) {
    // This iteration only supports using Ollama with nomic-embed-text.
    // The user must install and have nomic-embed-text running at
    // http://localhost::11434.
    KU_ASSERT(parameters.size() == 1);
    httplib::Client client("http://localhost:11434");
    httplib::Headers headers = {{"Content-Type", "application/json"}};
    result.resetAuxiliaryBuffer();
    for (auto selectedPos = 0u; selectedPos < resultSelVector->getSelSize(); ++selectedPos) {
        auto text = parameters[0]->getValue<ku_string_t>(selectedPos).getAsString();
        nlohmann::json payload = {{"model", "nomic-embed-text"}, {"prompt", text}};
        auto res = client.Post("/api/embeddings", headers, payload.dump(), "application/json");
        if (!res) {
            // TODO: Current server url is hardcoded. This must be changed when we accomodate
            // different endpoints.
            throw ConnectionException(
                "Request failed: Could not connect to server: http://localhost:11434\n");
        } else if (res->status != 200) {
            throw ConnectionException("Request failed with status " + std::to_string(res->status) +
                                      "\n Body: " + res->body + "\n");
        }

        auto embeddingVec = nlohmann::json::parse(res->body)["embedding"].get<std::vector<float>>();
        auto pos = (*resultSelVector)[selectedPos];
        auto resultEntry = ListVector::addList(&result, embeddingVec.size());
        result.setValue(pos, resultEntry);
        auto resultDataVector = ListVector::getDataVector(&result);
        auto resultPos = resultEntry.offset;
        for (auto i = 0u; i < embeddingVec.size(); i++) {
            resultDataVector->copyFromValue(resultPos++, Value(embeddingVec[i]));
        }
    }
}

static std::unique_ptr<FunctionBindData> bindFunc(const ScalarBindFuncInput& input) {
    std::vector<LogicalType> types;
    types.push_back(input.arguments[0]->getDataType().copy());
    KU_ASSERT(types.front() == LogicalType::STRING());
    static constexpr uint64_t NOMIC_EMBED_TEXT_EMBEDDING_DIMENSIONS = 768;
    return std::make_unique<FunctionBindData>(std::move(types),
        LogicalType::ARRAY(LogicalType(LogicalTypeID::FLOAT),
            NOMIC_EMBED_TEXT_EMBEDDING_DIMENSIONS));
}

function_set CreateEmbedding::getFunctionSet() {
    function_set functionSet;
    auto function = std::make_unique<ScalarFunction>(name,
        std::vector<LogicalTypeID>{LogicalTypeID::STRING}, LogicalTypeID::ARRAY, execFunc);
    function->bindFunc = bindFunc;
    functionSet.push_back(std::move(function));
    return functionSet;
}

} // namespace llm_extension
} // namespace kuzu
