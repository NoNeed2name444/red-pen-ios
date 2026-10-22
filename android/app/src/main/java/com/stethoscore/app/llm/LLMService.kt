package com.stethoscore.app.llm

import android.content.Context
import com.stethoscore.app.BuildConfig
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.network.SecureTokenStore

/**
 * Decides which backend answers, for every screen that wants a model. Port of
 * the cloud half of iOS Shared/LLM/LocalLLMService.swift: the cloud bearer
 * (the session, else the owner key), whose jobs a bearer reaches, why the
 * cloud cannot be used, and the backend itself.
 *
 * There is no writer to choose (the owner, 22 Oct): every text job goes to
 * the worker's writer route ([HostedProvider.cloud], model "cramdown-writer"),
 * which the worker sends to its Claude route for the owner key
 * (server/ai.js routeFor), inside the owner's monthly cap, and to the free
 * chain otherwise; PRO_PAYS and this phone's own $20.00 guard still hold.
 *
 * The owner key exists only in the owner's personal build
 * ([BuildConfig.OWNER_KEY], from the Gradle property `stethoscoreOwnerKey`;
 * iOS's Info.plist RedPenOwnerKey). With it empty - every public build - this
 * behaves as the iOS public build without Pro: Stethoscore Cloud is part of
 * Pro, nothing is sent. The key is never logged or put in a message.
 */
class LLMService(
    /** BuildConfig.OWNER_KEY: "" except in the personal build. */
    ownerKey: String,
    /** The saved session, when there is one. */
    private val session: () -> String?,
    private val baseUrl: String,
    private val transport: BackendClient.Transport = BackendClient.HttpTransport,
    /** What the owner key has spent; only the owner key's requests are counted. */
    val spend: OwnerSpend = OwnerSpend(OwnerSpend.MemoryStore()),
) {
    /** iOS ownerKey: present only when it is at least 32 characters, as the worker requires. */
    private val ownerKey: String? = ownerKey.takeIf { it.length >= 32 }

    /** The owner's personal build. */
    val isPersonal: Boolean get() = ownerKey != null

    /** Android has no subscriptions: only the personal build has Pro's cloud. */
    val isPro: Boolean get() = isPersonal

    /** The cloud models' bearer: a real session first, else the owner key. */
    val cloudToken: String? get() = session()?.trim()?.takeIf { it.isNotEmpty() } ?: ownerKey

    /** True when the cloud bearer is the owner key, so its spend is counted. */
    val usesOwnerKey: Boolean get() = ownerKey != null && cloudToken == ownerKey

    /** Whose jobs a bearer reaches: "owner" for the owner key; Android does not know the account's id yet. */
    fun cloudIdentity(bearer: String): String? = if (ownerKey != null && bearer == ownerKey) "owner" else null

    /** Why Stethoscore Cloud can't be used right now, or null when it can. */
    val cloudBlocker: String? get() = when {
        !isPro -> "${HostedProvider.BRAND} Cloud is part of Pro."
        cloudToken == null -> "Sign in to use ${HostedProvider.BRAND} Cloud."
        usesOwnerKey && spend.capReached -> OwnerSpend.CAP_REACHED
        else -> null
    }

    /** A client that sends this bearer to the worker, and only to the worker. */
    fun client(bearer: String?): BackendClient = BackendClient(baseUrl, { bearer }, transport)

    /** The writer route, always: null only while it is blocked ([cloudBlocker] says why). */
    fun backend(role: LLMRole = LLMRole.writer): LLMBackend? {
        val token = cloudToken
        if (cloudBlocker != null || token == null) return null
        return HostedLLMClient(HostedProvider.cloud(role), client(token), token, cloudIdentity(token),
            if (token == ownerKey) spend else null)
    }

    /** A short line saying what a role is using, for the generate screens. */
    fun summary(role: LLMRole = LLMRole.writer): String? =
        backend(role)?.let { if (it.isOnDevice) "${it.label}, on this device" else "${it.label}, hosted" }

    /** The checker's way in: a client with the cloud bearer, or why there is none. */
    fun checker(): Pair<BackendClient?, String?> {
        val token = cloudToken
        val blocker = cloudBlocker
        if (blocker != null || token == null) return null to (blocker ?: "Sign in to check accuracy.")
        return client(token) to null
    }

    companion object {
        private const val SPEND_KEY = "owner.spentMicros"

        /** The app's service: the worker in BuildConfig, the saved session, and the spend kept on this phone. */
        fun from(context: Context): LLMService {
            val app = context.applicationContext
            val shared = app.getSharedPreferences("llm", Context.MODE_PRIVATE)
            val store = object : OwnerSpend.Store {
                override fun read(): Long = runCatching { shared.getLong(SPEND_KEY, 0) }.getOrDefault(0)
                override fun write(micros: Long) { shared.edit().putLong(SPEND_KEY, micros).commit() }
            }
            val tokens = SecureTokenStore(app)
            return LLMService(BuildConfig.OWNER_KEY, { runCatching { tokens.read() }.getOrNull() },
                BuildConfig.WORKER_URL, spend = OwnerSpend(store))
        }
    }
}
