#pragma once

#include <base/types.h>

namespace DB
{

/// Check that `file_name` doesn't exceed the filesystem's NAME_MAX for the given directory.
/// Uses pathconf(directory_path, _PC_NAME_MAX) with NAME_MAX as fallback.
/// Throws ARGUMENT_OUT_OF_BOUND with entity_description in the message on violation.
void checkFileNameLength(const String & file_name, const String & directory_path, const String & entity_description);

/// Returns the filesystem's NAME_MAX for the given directory.
size_t getMaxFileNameLength(const String & directory_path);

}
