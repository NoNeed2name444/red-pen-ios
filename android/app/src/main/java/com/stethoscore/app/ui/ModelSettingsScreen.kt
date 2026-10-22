package com.stethoscore.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.stethoscore.app.llm.HostedProvider
import com.stethoscore.app.llm.LLMChoice
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle

/**
 * Settings > AI models. Port of the parts of iOS
 * Features/Support/ModelSettingsView.swift that Android has: the writer
 * (Off or Stethoscore Cloud) and Stethoscore Cloud's status, plus the
 * personal build's owner-key spend against its $20.00 cap. The on-device
 * models (Doctor-R1, Gemma), a provider with the student's own key, "Verify
 * what is generated" and the accuracy engine's background switch are not on
 * Android yet (parity.md). Ward parts only: option rows on the page's own
 * surface, no coloured buttons.
 */
@Composable
fun ModelSettingsScreen(onBack: () -> Unit, service: LLMService? = null) {
    val context = LocalContext.current
    val llm = service ?: remember { LLMService.from(context) }
    var choice by remember { mutableStateOf(llm.choice()) }
    val brandCloud = "${HostedProvider.BRAND} Cloud · Pro"
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        ScreenHeader("AI models", "The writer and ${HostedProvider.BRAND} Cloud", onBack)
        WardCard(Modifier.fillMaxWidth()) {
            SectionLabel("Use")
            Text("Writer", style = WardType.headline.textStyle())
            listOf(LLMChoice.off to "Off", LLMChoice.cloud to brandCloud).forEachIndexed { i, (option, label) ->
                WardOptionRow(
                    ('A' + i).toString(), label,
                    if (choice == option) ChartQuiz.Mark.chosen else ChartQuiz.Mark.idle,
                    modifier = Modifier
                        .clickable(role = Role.RadioButton) { llm.setChoice(option); choice = option }
                        .semantics { contentDescription = label; selected = choice == option },
                )
            }
            if (choice == LLMChoice.cloud) llm.cloudBlocker?.let { Note(it) }
            Note("The writer writes questions, OSCE stations, cards and textbook pages. Everything it writes is checked by the verification layer: safety checks on this device at once, then three model families solving each question without its answer, the literature, and a calibrated verdict on every item's badge. Verified means all three agree, nothing raised a concern and no safety check fired; anything less says Check this.")
        }
        WardCard(Modifier.fillMaxWidth()) {
            SectionLabel(brandCloud)
            Line("Writer", "Gemini 3.5 Flash")
            Line("Verification", "Three model families solving blind, the literature, a calibrated verdict")
            Line("Status", llm.cloudBlocker ?: "Ready")
            if (llm.isPersonal) {
                // the personal build's own guard: the owner key stops at the cap
                Line("Owner key spend", llm.spend.said)
                if (!llm.spend.capReached) Note("This build sends the owner key and stops sending it once ${OwnerSpend.dollars(llm.spend.capMicros)} has been spent, counted on this phone from what each reply reports, or at its most when it reports nothing.")
            }
            Note("Google's Gemini, with Google's Gemma and Cloudflare's models taking over when it is busy. Works on every device, including ones too small for the on-device models. Your text is sent to Google or Cloudflare to answer; ${HostedProvider.BRAND} does not keep it.")
        }
    }
}

@Composable private fun Line(label: String, value: String) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, Modifier.weight(1f), style = WardTextStyle.callout.textStyle(WardWeight.semibold))
        Text(value, Modifier.weight(1.4f), style = WardTextStyle.subheadline.textStyle(), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable private fun Note(text: String) {
    Text(text, style = WardType.caption.textStyle(), color = MaterialTheme.colorScheme.onSurfaceVariant)
}
