import { validateHandbook, type Handbook, type BookDocument, uid } from "./model";

const DB = "anytravel-handbooks-v1";
const MAX_BOOK_BYTES = 32 * 1024 * 1024;
let opening: Promise<IDBDatabase> | undefined;
function database(): Promise<IDBDatabase> {
  if (!opening) opening = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB, 1);
    request.onupgradeneeded = () => request.result.createObjectStore("books", { keyPath: "id" });
    request.onerror = () => { opening = undefined; reject(new Error("无法打开本机旅册存储，请检查浏览器的存储权限。")); };
    request.onblocked = () => { opening = undefined; reject(new Error("请关闭其他旧版页面，再打开手册。")); };
    request.onsuccess = () => { request.result.onversionchange = () => { request.result.close(); opening = undefined; }; resolve(request.result); };
  });
  return opening;
}
export async function listBooks(): Promise<Handbook[]> {
  const db = await database();
  return new Promise((resolve, reject) => { const r = db.transaction("books").objectStore("books").getAll(); r.onsuccess = () => resolve(r.result.sort((a: Handbook, b: Handbook) => b.updatedAt.localeCompare(a.updatedAt))); r.onerror = () => reject(r.error); });
}
export async function saveBook(book: Handbook): Promise<void> {
  validateHandbook(book);
  if (new Blob([JSON.stringify(book)]).size > MAX_BOOK_BYTES) throw new Error("这本手册超过 32 MB，请先导出备份，再移除较大的票据附件。");
  const db = await database();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("books", "readwrite"); tx.objectStore("books").put(book);
    tx.oncomplete = () => resolve(); tx.onabort = tx.onerror = () => reject(new Error("保存失败，可能是浏览器空间不足。修改尚未写入，请导出备份后重试。"));
  });
}
export async function deleteBook(id: string): Promise<void> {
  const db = await database();
  return new Promise((resolve, reject) => { const tx = db.transaction("books", "readwrite"); tx.objectStore("books").delete(id); tx.oncomplete = () => resolve(); tx.onabort = tx.onerror = () => reject(new Error("删除失败，请重试。")); });
}
export async function readDocument(file: File): Promise<BookDocument> {
  if (file.size > 5 * 1024 * 1024) throw new Error("单张票据最多 5 MB，请使用较小的 PDF 或图片。");
  const head = new Uint8Array(await file.slice(0, 16).arrayBuffer());
  const chars = String.fromCharCode(...head);
  const type = chars.startsWith("%PDF-") ? "application/pdf" : head[0] === 0x89 && chars.slice(1, 4) === "PNG" ? "image/png" : head[0] === 0xff && head[1] === 0xd8 ? "image/jpeg" : chars.startsWith("RIFF") && chars.slice(8, 12) === "WEBP" ? "image/webp" : null;
  if (!type) throw new Error("请选择有效的 PDF、PNG、JPEG 或 WebP 文件。");
  const data = await new Promise<string>((resolve, reject) => { const reader = new FileReader(); reader.onerror = () => reject(new Error("票据读取失败，请重新选择。")); reader.onload = () => resolve(String(reader.result).replace(/^data:[^;]*;/, `data:${type};`)); reader.readAsDataURL(file); });
  return { id: uid(), name: file.name, type, data };
}
export function download(data: BlobPart, name: string, type = "application/json") {
  const url = URL.createObjectURL(new Blob([data], { type }));
  const a = document.createElement("a"); a.href = url; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 30_000);
}
export function backup(book: Handbook) { download(JSON.stringify({ format: "anytravel-handbook", exportedAt: new Date().toISOString(), book }, null, 2), `${book.title.replace(/[\\/:*?"<>|]/g, "-")}-旅行手册.json`); }
