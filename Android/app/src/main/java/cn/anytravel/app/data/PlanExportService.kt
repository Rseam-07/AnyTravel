package cn.anytravel.app.data

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import androidx.core.content.FileProvider
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.TransportDirection
import java.io.File
import java.io.FileOutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

object PlanExportService {
    private const val AUTHORITY_SUFFIX = ".files"
    private val clockPattern = Regex("(\\d{1,2}):(\\d{2})")
    private val calendarFormatter = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss")

    fun exportPDF(context: Context, plan: CompletePlan) = exportFile(context, plan, "pdf") { file ->
        val document = PdfDocument()
        try {
            val writer = PdfWriter(document)
            writer.title("${plan.draft.destination} · ${plan.draft.dayCount}天")
            writer.muted("${plan.draft.origin.ifBlank { "出发地待定" }}出发 · ${plan.draft.travelers}人 · ${plan.draft.pace.title} · 当前预算轮廓约¥${plan.totalExpense}")
            writer.rule()
            plan.planningNotes.takeLast(4).forEach(writer::muted)
            plan.days.forEach { day ->
                writer.heading(day.title)
                day.schedule.forEach { item ->
                    writer.body("${item.timeText}  ${item.title}", bold = true)
                    writer.muted(item.detail)
                }
            }
            plan.selectedAccommodation?.let { hotel ->
                writer.heading("落脚 · ${hotel.name}")
                writer.body(hotel.address.ifBlank { "地址以预订页为准" })
                hotel.quotes.filter { it.amountCNY != null }.take(6).forEach { quote ->
                    writer.muted(quote.exportLine())
                }
            }
            listOf(TransportDirection.OUTBOUND, TransportDirection.RETURN).forEach { direction ->
                val option = plan.transports.firstOrNull { it.direction == direction && it.isRecommended }
                    ?: plan.transports.firstOrNull { it.direction == direction }
                option?.let {
                    writer.heading("${direction.title} · ${it.title}")
                    writer.body(listOfNotNull(it.departureTime, it.arrivalTime).joinToString(" → ").ifBlank { "时间以购买页为准" })
                    it.quotes.filter { quote -> quote.amountCNY != null }.take(4).forEach { quote -> writer.muted(quote.exportLine()) }
                }
            }
            writer.heading("费用")
            plan.expenses.forEach {
                val pending = if (it.unpricedComponents.isEmpty()) "" else " · 另待确认：${it.unpricedComponents.joinToString("、")}"
                writer.body("${it.title}  ${if (it.source == cn.anytravel.app.model.ExpenseSource.CONFIRMED) "" else "约"}¥${it.amountCNY} · ${it.detail} · ${it.source.title}$pending")
            }
            writer.body("当前预算轮廓约 ¥${plan.totalExpense}", bold = true)
            writer.muted("已确认支出 ¥${plan.confirmedExpense}" + if (plan.unpricedExpenseComponents.isEmpty()) "" else " · 另待确认：${plan.unpricedExpenseComponents.joinToString("、")}")
            writer.rule()
            writer.muted("价格、开放时间与库存会变化，请在出发和付款前复核。由 AnyTravel · 折叠远方生成。")
            writer.finish()
            FileOutputStream(file).use(document::writeTo)
        } finally {
            document.close()
        }
    }

    fun exportCalendar(context: Context, plan: CompletePlan) = exportFile(context, plan, "ics") { file ->
        file.writeText(calendarText(plan), Charsets.UTF_8)
    }

    internal fun calendarText(plan: CompletePlan, generatedAt: Instant = Instant.now()): String {
        val startDate = runCatching { LocalDate.parse(plan.draft.startDate) }.getOrNull()
            ?: throw IllegalArgumentException("行程还没有可导入日历的日期")
        val stamp = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
            .withZone(ZoneOffset.UTC)
            .format(generatedAt)
        val output = mutableListOf(
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//AnyTravel//Folded Distance//CN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:${escapeCalendar("${plan.draft.destination}旅行")}",
            "X-WR-TIMEZONE:Asia/Shanghai",
            "BEGIN:VTIMEZONE",
            "TZID:Asia/Shanghai",
            "BEGIN:STANDARD",
            "DTSTART:19700101T000000",
            "TZOFFSETFROM:+0800",
            "TZOFFSETTO:+0800",
            "TZNAME:CST",
            "END:STANDARD",
            "END:VTIMEZONE"
        )
        plan.days.forEach { day ->
            val date = startDate.plusDays(day.index.toLong())
            day.schedule.forEachIndexed { index, item ->
                val times = clockPattern.findAll(item.timeText).map { match ->
                    LocalTime.of(match.groupValues[1].toInt().coerceIn(0, 23), match.groupValues[2].toInt().coerceIn(0, 59))
                }.toList()
                val begin = times.firstOrNull() ?: LocalTime.of(9, 0).plusMinutes((index * 90).toLong())
                val end = times.getOrNull(1)?.takeIf { it.isAfter(begin) } ?: begin.plusHours(1)
                val stop = item.placeId?.let { id -> day.stops.firstOrNull { it.id == id } }
                output += listOf(
                    "BEGIN:VEVENT",
                    "UID:${escapeCalendar("${plan.id}-${item.id}@anytravel.cn")}",
                    "DTSTAMP:$stamp",
                    "DTSTART;TZID=Asia/Shanghai:${calendarFormatter.format(LocalDateTime.of(date, begin))}",
                    "DTEND;TZID=Asia/Shanghai:${calendarFormatter.format(LocalDateTime.of(date, end))}",
                    "SUMMARY:${escapeCalendar(item.title)}",
                    "DESCRIPTION:${escapeCalendar(item.detail)}",
                    "LOCATION:${escapeCalendar(stop?.address.orEmpty())}",
                    "STATUS:CONFIRMED",
                    "END:VEVENT"
                )
            }
        }
        output += "END:VCALENDAR"
        return output.joinToString("\r\n", postfix = "\r\n")
    }

    private fun exportFile(context: Context, plan: CompletePlan, extension: String, writer: (File) -> Unit): android.net.Uri {
        val directory = File(context.cacheDir, "shared_exports").apply { mkdirs() }
        val destination = plan.draft.destination.replace(Regex("[^\\p{L}\\p{N}_-]"), "_").take(32).ifBlank { "trip" }
        val file = File(directory, "AnyTravel-${destination}-${plan.id.take(8)}.$extension")
        writer(file)
        return FileProvider.getUriForFile(context, context.packageName + AUTHORITY_SUFFIX, file)
    }

    private fun PriceQuote.exportLine(): String = buildString {
        append(sourceLabel ?: provider)
        amountCNY?.let { append(" · ¥$it/${unit.title}") }
        totalAmountCNY?.let { append(" · 行程合计¥$it") }
        roomName?.takeIf(String::isNotBlank)?.let { append(" · $it") }
        mealPlan?.takeIf(String::isNotBlank)?.let { append(" · $it") }
        cancellationPolicy?.takeIf(String::isNotBlank)?.let { append(" · $it") }
    }

    private fun escapeCalendar(value: String): String = value
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")

    private class PdfWriter(private val document: PdfDocument) {
        private val pageWidth = 595
        private val pageHeight = 842
        private val margin = 46f
        private val bodyWidth = pageWidth - margin * 2
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(26, 43, 40) }
        private var pageNumber = 0
        private lateinit var page: PdfDocument.Page
        private lateinit var canvas: Canvas
        private var y = margin

        init { nextPage() }

        fun title(text: String) = paragraph(text, 25f, Color.rgb(12, 91, 83), true, 12f)
        fun heading(text: String) = paragraph(text, 17f, Color.rgb(12, 91, 83), true, 8f)
        fun body(text: String, bold: Boolean = false) = paragraph(text, 11.5f, Color.rgb(28, 38, 36), bold, 5f)
        fun muted(text: String) = paragraph(text, 9.5f, Color.rgb(96, 104, 102), false, 5f)

        fun rule() {
            ensure(22f)
            paint.color = Color.rgb(214, 224, 221)
            paint.strokeWidth = 1f
            canvas.drawLine(margin, y + 6f, pageWidth - margin, y + 6f, paint)
            y += 20f
        }

        fun finish() {
            document.finishPage(page)
        }

        private fun paragraph(text: String, size: Float, color: Int, bold: Boolean, bottom: Float) {
            val clean = text.trim()
            if (clean.isEmpty()) return
            paint.textSize = size
            paint.color = color
            paint.typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
            val lineHeight = size * 1.48f
            val lines = wrap(clean)
            lines.forEach { line ->
                ensure(lineHeight + bottom)
                canvas.drawText(line, margin, y + size, paint)
                y += lineHeight
            }
            y += bottom
        }

        private fun wrap(text: String): List<String> {
            val lines = mutableListOf<String>()
            text.lines().forEach { paragraph ->
                var remaining = paragraph
                while (remaining.isNotEmpty()) {
                    val count = paint.breakText(remaining, true, bodyWidth, null).coerceAtLeast(1)
                    lines += remaining.take(count)
                    remaining = remaining.drop(count)
                }
                if (paragraph.isEmpty()) lines += " "
            }
            return lines
        }

        private fun ensure(height: Float) {
            if (y + height <= pageHeight - margin) return
            document.finishPage(page)
            nextPage()
        }

        private fun nextPage() {
            pageNumber += 1
            page = document.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber).create())
            canvas = page.canvas
            canvas.drawColor(Color.rgb(252, 252, 248))
            y = margin
        }
    }
}
