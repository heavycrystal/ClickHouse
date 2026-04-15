#include <Common/computeMaxTableNameLength.h>
#include <Common/checkFileNameLength.h>
#include <Common/escapeForFileName.h>
#include <Interpreters/Context.h>

#include <filesystem>


namespace DB
{

size_t computeMaxTableNameLength(const String & database_name, ContextPtr context)
{
    namespace fs = std::filesystem;

    const String suffix = ".sql.detached";
    const String metadata_path = fs::path(context->getPath()) / "metadata";
    const String metadata_dropped_path = fs::path(context->getPath()) / "metadata_dropped";

    size_t max_create_length = getMaxFileNameLength(metadata_path) - suffix.length();
    size_t max_dropped_length = getMaxFileNameLength(metadata_dropped_path);

    size_t escaped_db_name_length = escapeForFileName(database_name).length();
    const size_t dot = 1;
    const size_t uuid_length = 36; // Standard UUID length
    const size_t extension_length = strlen(".sql");

    // Adjust for database name and UUID in dropped table filenames
    // Max path will look like this: ./metadata_dropped/{db_name}.{table_name}.{uuid}.{extension}
    size_t overhead = dot + escaped_db_name_length + dot + uuid_length + extension_length;
    size_t max_to_drop = (overhead >= max_dropped_length) ? 0 : max_dropped_length - overhead;

    // Return the minimum of the two calculated lengths
    return std::min(max_create_length, max_to_drop);
}
}
