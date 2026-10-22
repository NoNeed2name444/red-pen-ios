package com.stethoscore.app.audio

// What the phone learns about this lecturer, on the phone
// (ios/RedPen/Shared/PronunciationStore.swift and OnDeviceLearning.swift, fed0105).
//
// The recogniser is never retrained. What it cannot know is how the sounds it
// hears are SPELLED in English, and that is the only thing learned here. A
// mapping is applied as an exact lookup, so it cannot make the fuzzy
// matcher's mistakes.

enum class Evidence(val rawValue: String) {
    /** the spelling was on a slide of this lecture */
    slide("slide"),
    /** the student wrote it */
    correction("correction"),
    /** the same mapping recurred within a lecture */
    repetition("repetition");

    /**
     * How many independent sightings before the entry may rewrite a
     * transcript. A slide or a correction is already a person's own
     * spelling, so one is enough; repetition has to happen more than once.
     */
    val needed: Int get() = when (this) { slide, correction -> 1; repetition -> 3 }
}

data class Pronunciation(
    /** the sound */
    val key: String,
    /** how it is written in English */
    val spelling: String,
    /** one Arabic spelling, kept for the audit */
    val heardAs: String,
    /** evidence kind -> sightings */
    val counts: Map<String, Int>,
) {
    val isTrusted: Boolean get() = Evidence.values().any { (counts[it.rawValue] ?: 0) >= it.needed }
    val strongest: Evidence? get() = Evidence.values().firstOrNull { (counts[it.rawValue] ?: 0) >= it.needed }
}

class PronunciationStore {
    private val _entries = HashMap<String, Pronunciation>()
    val entries: Map<String, Pronunciation> get() = _entries
    /** sound-with-the-space-removed -> the key it was stored under */
    private val joined = HashMap<String, String>()

    fun copy(): PronunciationStore {
        val out = PronunciationStore()
        out._entries.putAll(_entries)
        out.joined.putAll(joined)
        return out
    }

    private fun index(key: String) { joined[SoundKey.collapsed(key)] = key }

    private fun entry(key: String): Pronunciation? {
        _entries[key]?.let { return it }
        val primary = joined[SoundKey.collapsed(key)] ?: return null
        return _entries[primary]
    }

    /**
     * A conflicting spelling for the same sound never silently wins: the
     * better-evidenced one is kept, and a tie keeps what was already there,
     * so a new guess cannot displace a slide or a correction.
     */
    fun add(sound: String, spelling: String, heardAs: String, evidence: Evidence): Boolean {
        if (sound.trim(' ', '\t').isEmpty() || spelling.trim(' ', '\t').isEmpty()) return false
        val existing = entry(sound)
        if (existing != null) {
            if (existing.spelling.equals(spelling, ignoreCase = true)) {
                val counts = existing.counts.toMutableMap()
                counts[evidence.rawValue] = (counts[evidence.rawValue] ?: 0) + 1
                _entries[existing.key] = existing.copy(counts = counts)
                index(existing.key)
                return true
            }
            val incoming = Pronunciation(sound, spelling, heardAs, mapOf(evidence.rawValue to 1))
            if (!incoming.isTrusted || existing.isTrusted) return false
            _entries.remove(existing.key)
            _entries[sound] = incoming
            index(sound)
            return true
        }
        _entries[sound] = Pronunciation(sound, spelling, heardAs, mapOf(evidence.rawValue to 1))
        index(sound)
        return true
    }

    /**
     * Forget one sound entirely. Undo needs this: a correction taken back must
     * stop teaching the spelling it taught.
     */
    fun forget(sound: String): Boolean {
        val flat = SoundKey.collapsed(sound)
        var removed = _entries.remove(sound) != null
        val primary = joined[flat]
        if (primary != null && primary != sound) removed = _entries.remove(primary) != null || removed
        joined.remove(flat)
        return removed
    }

    fun spelling(span: List<String>): String? {
        val hit = entry(SoundKey.of(span)) ?: return null
        return if (hit.isTrusted) hit.spelling else null
    }

    /** What [apply] gives back: the text, and each span replaced with what replaced it. */
    data class Applied(val text: String, val hits: List<Pair<String, String>>)

    /** Replace every span the store knows. Longest span first, so a two-word term is never broken by the one-word entry that is its first half. */
    fun apply(text: String, maxSpan: Int = 3): Applied {
        val tokens = text.split(' ').filter { it.isNotEmpty() }
        val out = ArrayList<String>()
        val hits = ArrayList<Pair<String, String>>()
        var i = 0
        while (i < tokens.size) {
            var matched = false
            var n = minOf(maxSpan, tokens.size - i)
            while (n >= 1) {
                val span = tokens.subList(i, i + n)
                val english = if (span.any(SoundKey::hasArabic)) spelling(span) else null
                if (english != null) {
                    val head = tokens[i]
                    val article = SoundKey.stripArticle(head) != head && SoundKey.clusters(head).size > 3
                    out.add(if (article) "الـ $english" else english)
                    hits.add(span.joinToString(" ") to english)
                    i += n
                    matched = true
                    break
                }
                n -= 1
            }
            if (!matched) {
                out.add(tokens[i])
                i += 1
            }
        }
        return Applied(out.joinToString(" "), hits)
    }

    // MARK: file format - the same tab-separated table the pipeline uses

    fun tsv(): String = _entries.values.sortedBy { it.spelling }.joinToString("\n") { e ->
        val ev = Evidence.values().filter { (e.counts[it.rawValue] ?: 0) > 0 }
            .joinToString(",") { "${it.rawValue}:${e.counts[it.rawValue] ?: 0}" }
        "${e.heardAs}\t${e.spelling}\t$ev"
    }

    companion object {
        fun fromTSV(text: String): PronunciationStore {
            val store = PronunciationStore()
            for (raw in text.split('\n')) {
                if (raw.isEmpty()) continue
                val line = raw.takeWhile { it != '#' }
                val parts = line.split('\t')
                if (parts.size < 2) continue
                val heard = parts[0].trim(' ', '\t')
                val spelling = parts[1].trim(' ', '\t')
                if (heard.isEmpty() || spelling.isEmpty()) continue
                val counts = HashMap<String, Int>()
                if (parts.size >= 3) {
                    for (token in parts[2].split(',').filter { it.isNotEmpty() }) {
                        val kv = token.split(':').filter { it.isNotEmpty() }
                        val n = kv.getOrNull(1)?.toIntOrNull()
                        if (kv.size == 2 && n != null) counts[kv[0]] = n
                        else token.toIntOrNull()?.let { counts[Evidence.repetition.rawValue] = it }
                    }
                }
                if (counts.isEmpty()) counts[Evidence.correction.rawValue] = 1
                val key = SoundKey.of(heard.split(' ').filter { it.isNotEmpty() })
                if (key.trim(' ', '\t').isEmpty()) continue
                store._entries[key] = Pronunciation(key, spelling, heard, counts)
                store.index(key)
            }
            return store
        }
    }
}

/**
 * Learning a lecturer's pronunciations from one lecture, on the phone: from
 * the slides (his own spelling), the student's corrections, and a mapping
 * that recurs. No audio leaves the phone and no model is retrained.
 */
object OnDeviceLearning {
    /** Terms the slides spell out: the lecturer's own spelling of the words he is about to say. */
    fun fromSlides(transcript: String, slideText: List<String>, store: PronunciationStore): Int {
        val phrases = ArrayList<Pair<String, String>>()
        for (slide in slideText) {
            val words = slide.split(Regex("[^\\p{L}\\p{M}-]+")).filter { it.isNotEmpty() }
            for (width in 1..2) {
                if (words.size < width) continue
                for (start in 0..(words.size - width)) {
                    val phrase = words.subList(start, start + width)
                    val usable = phrase.all { word -> SoundKey.clusters(word).size >= 3 && word.all { it.code < 128 } }
                    if (!usable) continue
                    val key = SoundKey.of(phrase)
                    if (key.replace(" ", "").length >= 4) phrases.add(key to phrase.joinToString(" "))
                }
            }
        }
        if (phrases.isEmpty()) return 0
        val bySound = HashMap<String, String>()
        for ((key, spelling) in phrases) {
            if (key !in bySound) bySound[key] = spelling
            val flat = SoundKey.collapsed(key)
            if (flat !in bySound) bySound[flat] = spelling
        }
        val tokens = transcript.split(' ').filter { it.isNotEmpty() }
        var learned = 0
        var i = 0
        while (i < tokens.size) {
            var n = minOf(2, tokens.size - i)
            var matched = false
            while (n >= 1) {
                val span = tokens.subList(i, i + n)
                val key = SoundKey.of(span)
                val spelling = if (span.any(SoundKey::hasArabic)) bySound[key] ?: bySound[SoundKey.collapsed(key)] else null
                if (spelling != null) {
                    if (store.add(key, spelling, span.joinToString(" "), Evidence.slide)) learned += 1
                    i += n
                    matched = true
                    break
                }
                n -= 1
            }
            if (!matched) i += 1
        }
        return learned
    }

    /** The student edited a word. Whatever they wrote is how it is spelled. */
    fun fromCorrection(heard: List<String>, wrote: String, store: PronunciationStore): Boolean =
        store.add(SoundKey.of(heard), wrote, heard.joinToString(" "), Evidence.correction)

    /**
     * The deterministic repair mapped the same sound to the same term more
     * than once in a lecture. A sound that produced two DIFFERENT terms
     * teaches nothing at all.
     */
    fun fromRepetition(repairs: List<Pair<String, String>>, store: PronunciationStore): Int {
        val seen = LinkedHashMap<String, LinkedHashMap<String, Int>>()
        val heardAs = HashMap<String, String>()
        for ((heard, term) in repairs) {
            val key = SoundKey.of(heard.split(' ').filter { it.isNotEmpty() })
            if (key.trim(' ', '\t').isEmpty()) continue
            val terms = seen.getOrPut(key) { LinkedHashMap() }
            terms[term] = (terms[term] ?: 0) + 1
            heardAs[key] = heard
        }
        var learned = 0
        for ((key, terms) in seen) {
            if (terms.size != 1) continue
            val (term, times) = terms.entries.first()
            if (times < Evidence.repetition.needed) continue
            repeat(times) { store.add(key, term, heardAs[key] ?: "", Evidence.repetition) }
            learned += 1
        }
        return learned
    }
}
