package com.stethoscore.app.data

import org.junit.Assert.assertTrue
import org.junit.Test

// A port of the "tags" part of ios/RedPen/Tests/DataIOTests.swift
// (fed0105), case for case: what the tag field stores, the search hooks and
// the counts behind the suggestions. The rest of DataIOTests (APKG, CSV and
// plain-text import, old files) is the importers' and comes with them.
class CardTagsTest {
    private fun check(label: String, ok: Boolean) = assertTrue(label, ok)

    @Test fun tags() {
        check("tags: typed words become tags", CardTags.parse("cardio pharm cardio") == listOf("cardio", "pharm"))
        check("tags: a comma list keeps spaces as _", CardTags.parse("heart failure, renal") == listOf("heart_failure", "renal"))
        check("tags: adding twice adds once", CardTags.adding("Cardio", listOf("cardio")) == listOf("cardio"))
        check("tags: removing the last leaves nothing stored", CardTags.removing("x", listOf("x")) == null)
        check("tags: a chip shows the last level", CardTags.label("#AK_Step1::Cardio") == "Cardio")
        val search = CardTags.query("aortic tag:pharm #AK_Step1 valve")
        check("search: tag words pulled out of the text", search.first == "aortic valve" && search.second == listOf("pharm", "AK_Step1"))
        check("search: a parent tag finds its children", CardTags.tag("#AK_Step1::Cardio", "ak_step1"))
        check("search: a prefix of a name is not a parent", !CardTags.tag("pharmacology", "pharm"))
        check("search: a deeper level is found by its own name", CardTags.tag("#AK_Step1_v12::#B&B::Cardio", "cardio")
            && CardTags.tag("#AK_Step1::Cardio::HF", "#cardio") && CardTags.tag("a::b::c", "b::c"))
        check("search: whole levels only", !CardTags.tag("#AK_Step1::Cardiology", "cardio")
            && !CardTags.tag("a::b::c", "a::c"))
        var tagged = StudySet(name = "T", kind = StudySetKind.ANKI,
            cards = listOf(AnkiCard(type = AnkiCardType.QA, front = "a", bullets = listOf("b")), AnkiCard(type = AnkiCardType.QA, front = "c", bullets = listOf("d"))))
        tagged = tagged.copy(cards = tagged.cards.mapIndexed { i, c -> if (i == 1) c.copy(tags = listOf("renal::loop")) else c })
        check("search: only the tagged cards of a set", CardTags.tagged(tagged, listOf("renal"))?.cards?.size == 1)
        tagged = tagged.copy(tags = listOf("renal"))
        check("search: a set's tag covers every card", CardTags.tagged(tagged, listOf("renal"))?.cards?.size == 2)
        check("search: nothing tagged is nil", CardTags.tagged(tagged, listOf("neuro")) == null)
        val counted = CardTags.counts(listOf(tagged))
        check("counts: most used first", counted.firstOrNull()?.tag == "renal" && counted.firstOrNull()?.count == 1 && counted.size == 2)
        check("suggestions: what starts with the typing, not what is chosen",
            CardTags.suggestions("ren", counted, listOf("renal")) == listOf("renal::loop"))
    }
}
