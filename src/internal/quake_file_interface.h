/*
 * vkQuake RmlUI - Quake-Aware File Interface
 *
 * Custom Rml::FileInterface that uses Quake's virtual filesystem
 * (COM_FOpenFile + FS_* wrappers) for file I/O. This ensures
 * correct search path resolution and pak file support.
 *
 * Search order:
 *   1. Quake VFS via COM_FOpenFile (game dirs, pak files)
 *   2. Basedir-relative fallback (loose files at project root)
 */

#ifndef QRMLUI_QUAKE_FILE_INTERFACE_H
#define QRMLUI_QUAKE_FILE_INTERFACE_H

#include <RmlUi/Core/FileInterface.h>

namespace QRmlUI {

class QuakeFileInterface : public Rml::FileInterface {
public:
    Rml::FileHandle Open(const Rml::String& path) override;
    void Close(Rml::FileHandle file) override;
    size_t Read(void* buffer, size_t size, Rml::FileHandle file) override;
    bool Seek(Rml::FileHandle file, long offset, int origin) override;
    size_t Tell(Rml::FileHandle file) override;
    size_t Length(Rml::FileHandle file) override;
};

} // namespace QRmlUI

#endif /* QRMLUI_QUAKE_FILE_INTERFACE_H */
