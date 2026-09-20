package com.example.tiny_computer.filepicker;

import android.annotation.TargetApi;
import android.content.res.AssetFileDescriptor;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.graphics.Point;
import android.os.Build;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract.Document;
import android.provider.DocumentsContract.Root;
import android.provider.DocumentsProvider;
import android.webkit.MimeTypeMap;

import com.example.tiny_computer.R;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.Collections;
import java.util.LinkedList;

//This file is mainly copied from Termux :P

/**
 * A document provider for the Storage Access Framework which exposes the files in the
 * $HOME/ directory to other apps.
 * <p/>
 * Note that this replaces providing an activity matching the ACTION_GET_CONTENT intent:
 * <p/>
 * "A document provider and ACTION_GET_CONTENT should be considered mutually exclusive. If you
 * support both of them simultaneously, your app will appear twice in the system picker UI,
 * offering two different ways of accessing your stored data. This would be confusing for users."
 * - http://developer.android.com/guide/topics/providers/document-provider.html#43
 */
public class TinyDocumentsProvider extends DocumentsProvider {

    private static final String ALL_MIME_TYPES = "*/*";



    // The default columns to return information about a root if no specific
    // columns are requested in a query.
    private static final String[] DEFAULT_ROOT_PROJECTION = new String[]{
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_FLAGS,
            Root.COLUMN_ICON,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_AVAILABLE_BYTES
    };

    // The default columns to return information about a document if no specific
    // columns are requested in a query.
    private static final String[] DEFAULT_DOCUMENT_PROJECTION = new String[]{
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE
    };

    @Override
    public Cursor queryRoots(String[] projection) {
        final MatrixCursor result = new MatrixCursor(projection != null ? projection : DEFAULT_ROOT_PROJECTION);
        final String applicationName = getContext().getString(R.string.tc_app_name);
        final File BASE_DIR = new File(getContext().getFilesDir(), "containers");
        final MatrixCursor.RowBuilder row = result.newRow();
        row.add(Root.COLUMN_ROOT_ID, getDocIdForFile(BASE_DIR));
        row.add(Root.COLUMN_DOCUMENT_ID, getDocIdForFile(BASE_DIR));
        row.add(Root.COLUMN_SUMMARY, null);
        row.add(Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_CREATE | Root.FLAG_SUPPORTS_SEARCH | Root.FLAG_SUPPORTS_IS_CHILD);
        row.add(Root.COLUMN_TITLE, applicationName);
        row.add(Root.COLUMN_MIME_TYPES, ALL_MIME_TYPES);
        row.add(Root.COLUMN_AVAILABLE_BYTES, BASE_DIR.getFreeSpace());
        row.add(Root.COLUMN_ICON, R.mipmap.ic_launcher);
        return result;
    }

    @Override
    public Cursor queryDocument(String documentId, String[] projection) throws FileNotFoundException {
        final MatrixCursor result = new MatrixCursor(projection != null ? projection : DEFAULT_DOCUMENT_PROJECTION);
        // TINY-OPT: 原来这里把 null 当 file 参数传进去，includeFile 内部会再调
        // getFileForDocId 把局部变量覆盖成 null，随后 file.isDirectory() 直接 NPE
        // （系统文件管理器一进容器目录就可能崩）。这里显式把 File 查好再传。
        final File file = getFileForDocId(documentId);
        includeFile(result, documentId != null ? documentId : getDocIdForFile(file), file);
        return result;
    }

    @Override
    public Cursor queryChildDocuments(String parentDocumentId, String[] projection, String sortOrder) throws FileNotFoundException {
        return queryChildDocuments(parentDocumentId, projection, sortOrder, null);
    }

    @Override
    public Cursor queryChildDocuments(String parentDocumentId, String[] projection, String sortOrder,
                                      CancellationSignal cancellationSignal) throws FileNotFoundException {
        final MatrixCursor result = new MatrixCursor(projection != null ? projection : DEFAULT_DOCUMENT_PROJECTION);
        final File parent = getFileForDocId(parentDocumentId);
        final File[] children = parent.listFiles();
        // TINY-OPT: listFiles() 在权限/IO 错误时返回 null，原来直接 for-each 会 NPE。
        if (children == null) {
            return result;
        }
        // TINY-OPT: 原来不理会 sortOrder，也不响应取消信号。容器 rootfs 里 /usr/share
        // 这类目录有上万个条目，Binder 线程会被长时间占用且无法取消，文件管理器会卡死。
        if (sortOrder != null && sortOrder.length() > 0) {
            try {
                java.util.Arrays.sort(children, new java.util.Comparator<File>() {
                    @Override
                    public int compare(File a, File b) {
                        return a.getName().compareToIgnoreCase(b.getName());
                    }
                });
            } catch (Throwable ignored) {
                // 排序失败不影响正确性，退化成目录原始顺序
            }
        }
        for (File file : children) {
            if (cancellationSignal != null && cancellationSignal.isCanceled()) {
                break;
            }
            includeFile(result, null, file);
        }
        return result;
    }

    @Override
    public ParcelFileDescriptor openDocument(final String documentId, String mode, CancellationSignal signal) throws FileNotFoundException {
        final File file = getFileForDocId(documentId);
        final int accessMode = ParcelFileDescriptor.parseMode(mode);
        return ParcelFileDescriptor.open(file, accessMode);
    }

    @Override
    public AssetFileDescriptor openDocumentThumbnail(String documentId, Point sizeHint, CancellationSignal signal) throws FileNotFoundException {
        final File file = getFileForDocId(documentId);
        // TINY-OPT: 原来把整个原文件当缩略图返回，而 includeFile 又对所有 image/* 置了
        // FLAG_SUPPORTS_THUMBNAIL，系统会去解码一张几十 MB 的原图。超过 512KB 的直接
        // 返回 null，交给系统自己处理或显示通用图标。
        if (file.length() > 512 * 1024) {
            return null;
        }
        final ParcelFileDescriptor pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
        return new AssetFileDescriptor(pfd, 0, file.length());
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String createDocument(String parentDocumentId, String mimeType, String displayName) throws FileNotFoundException {
        // TINY-OPT: documentId 就是绝对路径，但展示名不能直接当文件名用（可能含 ../ 或
        // 路径分隔符）。原来直接把 displayName 拼进路径，存在越界写入的可能。
        final File parent = getFileForDocId(parentDocumentId);
        final String safeName = sanitizeDisplayName(displayName);
        File newFile = new File(parent, safeName);
        int noConflictId = 2;
        while (newFile.exists()) {
            newFile = new File(parent, safeName + " (" + noConflictId++ + ")");
        }
        try {
            boolean succeeded;
            if (Document.MIME_TYPE_DIR.equals(mimeType)) {
                succeeded = newFile.mkdir();
            } else {
                succeeded = newFile.createNewFile();
            }
            if (!succeeded) {
                throw new FileNotFoundException("Failed to create document with id " + newFile.getPath());
            }
        } catch (IOException e) {
            throw new FileNotFoundException("Failed to create document with id " + newFile.getPath());
        }
        return newFile.getPath();
    }

    private static String sanitizeDisplayName(String displayName) {
        String name = displayName == null ? "" : displayName;
        name = name.replace("/", "_").replace("\\", "_");
        while (name.contains("..")) {
            name = name.replace("..", "_");
        }
        name = name.trim();
        return name.isEmpty() ? "untitled" : name;
    }

    @Override
    public void deleteDocument(String documentId) throws FileNotFoundException {
        File file = getFileForDocId(documentId);
        if (!file.delete()) {
            throw new FileNotFoundException("Failed to delete document with id " + documentId);
        }
    }

    @Override
    public String getDocumentType(String documentId) throws FileNotFoundException {
        File file = getFileForDocId(documentId);
        return getMimeType(file);
    }

    @Override
    public Cursor querySearchDocuments(String rootId, String query, String[] projection) throws FileNotFoundException {
        final MatrixCursor result = new MatrixCursor(projection != null ? projection : DEFAULT_DOCUMENT_PROJECTION);
        final File parent = getFileForDocId(rootId);

        // This example implementation searches file names for the query and doesn't rank search
        // results, so we can stop as soon as we find a sufficient number of matches.  Other
        // implementations might rank results and use other data about files, rather than the file
        // name, to produce a match.
        final LinkedList<File> pending = new LinkedList<>();
        pending.add(parent);

        // TINY-OPT: query 统一小写化（配合下面文件名的小写化比较）
        final String normalizedQuery = query == null ? "" : query.toLowerCase(java.util.Locale.ROOT);

        final int MAX_SEARCH_RESULTS = 50;
        while (!pending.isEmpty() && result.getCount() < MAX_SEARCH_RESULTS) {
            final File file = pending.removeFirst();
            // Avoid directories outside the $HOME directory linked with symlinks (to avoid e.g. search
            // through the whole SD card).
            boolean isInsideHome;
            try {
                isInsideHome = file.getCanonicalPath().startsWith(new File(getContext().getFilesDir(), "containers").getAbsolutePath());
            } catch (IOException e) {
                isInsideHome = true;
            }
            if (isInsideHome) {
                if (file.isDirectory()) {
                    // TINY-OPT: listFiles() 可能返回 null，原来直接 addAll 会 NPE。
                    final File[] kids = file.listFiles();
                    if (kids != null) {
                        Collections.addAll(pending, kids);
                    }
                } else {
                    // TINY-OPT: 原来只把文件名小写化，query 没有，搜 “Documents” 永远搜不到。
                    if (normalizedQuery.length() > 0
                            && file.getName().toLowerCase(java.util.Locale.ROOT).contains(normalizedQuery)) {
                        includeFile(result, null, file);
                    }
                }
            }
        }

        return result;
    }

    @Override
    public boolean isChildDocument(String parentDocumentId, String documentId) {
        // TINY-OPT: 原来直接用 startsWith 做前缀判断，/…/containers/01 会被判成
        // /…/containers/0 的子项。这里补上路径分隔符边界。
        if (parentDocumentId == null || documentId == null) {
            return false;
        }
        final String parent = new File(parentDocumentId).getAbsolutePath();
        final String child = new File(documentId).getAbsolutePath();
        if (child.equals(parent)) {
            return true;
        }
        final String prefix = parent.endsWith(File.separator) ? parent : parent + File.separator;
        return child.startsWith(prefix);
    }

    /**
     * Get the document id given a file. This document id must be consistent across time as other
     * applications may save the ID and use it to reference documents later.
     * <p/>
     * The reverse of @{link #getFileForDocId}.
     */
    private static String getDocIdForFile(File file) {
        return file.getAbsolutePath();
    }

    /**
     * Get the file given a document id (the reverse of {@link #getDocIdForFile(File)}).
     */
    private static File getFileForDocId(String docId) throws FileNotFoundException {
        final File f = new File(docId);
        if (!f.exists()) throw new FileNotFoundException(f.getAbsolutePath() + " not found");
        // TINY-OPT: documentId 就是绝对路径，原来只校验“存在”，任意绝对路径都会被接受。
        // 这里限制在应用自己的 files/containers 目录内（与 querySearchDocuments 的
        // canonical 判断保持一致），超界的一律当作不存在。
        final File base = containerBaseDir();
        if (base != null && !isInsideBaseDir(f, base)) {
            throw new FileNotFoundException(f.getAbsolutePath() + " is outside of container dir");
        }
        return f;
    }

    // TINY-OPT: 工具方法，判断 path 是否位于 base 目录内（用于 containment 校验）。
    private static boolean isInsideBaseDir(File file, File base) {
        try {
            final String canonical = file.getCanonicalPath();
            final String basePath = base.getCanonicalPath();
            return canonical.equals(basePath) || canonical.startsWith(basePath + File.separator);
        } catch (IOException e) {
            return false;
        }
    }

    // TINY-OPT: provider 的根目录固定为 files/containers；getFileForDocId 只接受
    // 该目录内的路径。取不到 Context 时（理论上不该发生）退化为“允许”，避免把
    // 文件管理器整个弄坏。
    private static File containerBaseDir() {
        try {
            return new File(com.example.tiny_computer.MainApplication.getAppContext().getFilesDir(), "containers");
        } catch (Throwable t) {
            return null;
        }
    }

    private static String getMimeType(File file) {
        if (file.isDirectory()) {
            return Document.MIME_TYPE_DIR;
        } else {
            final String name = file.getName();
            final int lastDot = name.lastIndexOf('.');
            if (lastDot >= 0) {
                final String extension = name.substring(lastDot + 1).toLowerCase();
                final String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
                if (mime != null) return mime;
            }
            return "application/octet-stream";
        }
    }

    /**
     * Add a representation of a file to a cursor.
     *
     * @param result the cursor to modify
     * @param docId  the document ID representing the desired file (may be null if given file)
     * @param file   the File object representing the desired file (may be null if given docID)
     */
    private void includeFile(MatrixCursor result, String docId, File file)
            throws FileNotFoundException {
        if (file == null) {
            // TINY-OPT: 两个参数都为 null 时原本会直接 NPE，这里明确报错。
            if (docId == null) {
                throw new FileNotFoundException("includeFile: both docId and file are null");
            }
            file = getFileForDocId(docId);
        }
        if (docId == null) {
            docId = getDocIdForFile(file);
        }

        int flags = 0;
        if (file.isDirectory()) {
            if (file.canWrite()) flags |= Document.FLAG_DIR_SUPPORTS_CREATE;
        } else if (file.canWrite()) {
            flags |= Document.FLAG_SUPPORTS_WRITE;
        }
        // TINY-OPT: getParentFile() 对文件系统根目录会返回 null，原来直接 .canWrite() 会 NPE。
        final File parentFile = file.getParentFile();
        if (parentFile != null && parentFile.canWrite()) flags |= Document.FLAG_SUPPORTS_DELETE;

        final String displayName = file.getName();
        final String mimeType = getMimeType(file);
        if (mimeType.startsWith("image/")) flags |= Document.FLAG_SUPPORTS_THUMBNAIL;

        final MatrixCursor.RowBuilder row = result.newRow();
        row.add(Document.COLUMN_DOCUMENT_ID, docId);
        row.add(Document.COLUMN_DISPLAY_NAME, displayName);
        row.add(Document.COLUMN_SIZE, file.length());
        row.add(Document.COLUMN_MIME_TYPE, mimeType);
        row.add(Document.COLUMN_LAST_MODIFIED, file.lastModified());
        row.add(Document.COLUMN_FLAGS, flags);
        row.add(Document.COLUMN_ICON, R.mipmap.ic_launcher);
    }

}