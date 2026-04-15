#include <Common/checkFileNameLength.h>
#include <Common/Exception.h>

#include <climits>
#include <unistd.h>

namespace DB
{

namespace ErrorCodes
{
    extern const int ARGUMENT_OUT_OF_BOUND;
}

size_t getMaxFileNameLength(const String & directory_path)
{
    auto length = pathconf(directory_path.c_str(), _PC_NAME_MAX);
    return (length == -1) ? NAME_MAX : static_cast<size_t>(length);
}

void checkFileNameLength(const String & file_name, const String & directory_path, const String & entity_description)
{
    size_t max_length = getMaxFileNameLength(directory_path);
    if (file_name.size() > max_length)
    {
        throw Exception(
            ErrorCodes::ARGUMENT_OUT_OF_BOUND,
            "The file name for {} is too long ({} bytes, maximum is {} bytes)",
            entity_description, file_name.size(), max_length);
    }
}

}
