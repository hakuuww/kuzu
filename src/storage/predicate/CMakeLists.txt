add_library(kuzu_storage_predicate
        OBJECT
        null_predicate.cpp
        column_predicate.cpp
        constant_predicate.cpp)

set(ALL_OBJECT_FILES
        ${ALL_OBJECT_FILES} $<TARGET_OBJECTS:kuzu_storage_predicate>
        PARENT_SCOPE)
