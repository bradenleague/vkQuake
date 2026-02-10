/*
 * vkQuake RmlUI - Quake-Aware File Interface Implementation
 *
 * Uses Quake's virtual filesystem (COM_FOpenFile + FS_* wrappers)
 * for pak file support and correct search path resolution. Falls
 * back to basedir-relative lookup for loose files at the project
 * root (e.g. <basedir>/ui/...) which are outside game directories.
 */

#include "quake_file_interface.h"
#include "engine_bridge.h"

#include <cstdio>
#include <string>

namespace QRmlUI
{
namespace
{

struct QFileHandle
{
	fshandle_t fh;
};

/* Helper: open a loose file and populate an fshandle_t for it. */
static Rml::FileHandle OpenLoose (FILE *f)
{
	fseek (f, 0, SEEK_END);
	long length = ftell (f);
	fseek (f, 0, SEEK_SET);

	auto *qfh = new QFileHandle;
	qfh->fh.file = f;
	qfh->fh.pak = 0;
	qfh->fh.start = 0;
	qfh->fh.pos = 0;
	qfh->fh.length = length;
	return reinterpret_cast<Rml::FileHandle> (qfh);
}

} // anonymous namespace

Rml::FileHandle QuakeFileInterface::Open (const Rml::String &path)
{
	/* 1. Quake VFS: game dirs + pak files (handles mod overrides,
	 *    pak-embedded assets, and the full engine search order). */
	FILE *file = nullptr;
	int	  length = COM_FOpenFile (path.c_str (), &file, nullptr);
	if (length != -1 && file)
	{
		auto *qfh = new QFileHandle;
		qfh->fh.file = file;
		qfh->fh.pak = file_from_pak; // capture immediately after COM_FOpenFile
		qfh->fh.start = ftell (file);
		qfh->fh.pos = 0;
		qfh->fh.length = length;
		return reinterpret_cast<Rml::FileHandle> (qfh);
	}

	/* 2. Basedir-relative: base UI files live at <basedir>/ui/...,
	 *    which is outside the game search paths (id1/, mod/, etc.). */
	if (com_basedir[0] != '\0')
	{
		std::string base_path = std::string (com_basedir) + "/" + path.c_str ();
		FILE	   *f = fopen (base_path.c_str (), "rb");
		if (f)
			return OpenLoose (f);
	}

	return 0;
}

void QuakeFileInterface::Close (Rml::FileHandle file)
{
	auto *qfh = reinterpret_cast<QFileHandle *> (file);
	FS_fclose (&qfh->fh);
	delete qfh;
}

size_t QuakeFileInterface::Read (void *buffer, size_t size, Rml::FileHandle file)
{
	auto *qfh = reinterpret_cast<QFileHandle *> (file);
	return FS_fread (buffer, 1, size, &qfh->fh);
}

bool QuakeFileInterface::Seek (Rml::FileHandle file, long offset, int origin)
{
	auto *qfh = reinterpret_cast<QFileHandle *> (file);
	return FS_fseek (&qfh->fh, offset, origin) == 0;
}

size_t QuakeFileInterface::Tell (Rml::FileHandle file)
{
	auto *qfh = reinterpret_cast<QFileHandle *> (file);
	return static_cast<size_t> (FS_ftell (&qfh->fh));
}

size_t QuakeFileInterface::Length (Rml::FileHandle file)
{
	auto *qfh = reinterpret_cast<QFileHandle *> (file);
	return static_cast<size_t> (FS_filelength (&qfh->fh));
}

} // namespace QRmlUI
