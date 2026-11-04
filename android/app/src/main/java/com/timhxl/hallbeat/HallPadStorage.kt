package com.timhxl.hallbeat

import android.content.Context
import androidx.datastore.core.CorruptionException
import androidx.datastore.core.DataMigration
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.Serializer
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.json.JSONObject
import top.ltfan.m3x.datastore.DataStoreStore
import top.ltfan.m3x.datastore.MutableStore
import top.ltfan.m3x.datastore.compose.mutableStateStore

/** 使用 M3X 管理本地设置；每个文件在进程内只有一个存储实例。 */
internal class HallPadStorage private constructor(context: Context) {
    private val app = context.applicationContext
    private val uiScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val display = create("hallpad_display")
    val configuration = create("hallpad_configuration")
    suspend fun awaitInitialized() { display.store.awaitInitialized(); configuration.store.awaitInitialized() }
    private fun create(name: String): StoredPreferences {
        val legacy = app.getSharedPreferences(name, Context.MODE_PRIVATE)
        val migration = object : DataMigration<Map<String, String>> {
            override suspend fun shouldMigrate(currentData: Map<String, String>): Boolean = currentData["_migrated"] != "1"
            override suspend fun migrate(currentData: Map<String, String>): Map<String, String> = legacy.all.mapNotNull { (key, value) -> value?.let { key to it.toString() } }.toMap() + currentData + ("_migrated" to "1")
            // 保留旧文件作为迁移备份，后续读取始终使用 DataStore。
            override suspend fun cleanUp() = Unit
        }
        val dataStore = DataStoreFactory.create(serializer = StringMapSerializer, migrations = listOf(migration), scope = ioScope, produceFile = { File(app.filesDir, "datastore/$name.json") })
        return StoredPreferences(mutableStateStore(store = DataStoreStore(dataStore), scope = uiScope, initialValue = emptyMap()))
    }
    companion object {
        @Volatile private var instance: HallPadStorage? = null
        fun get(context: Context): HallPadStorage = instance ?: synchronized(this) { instance ?: HallPadStorage(context).also { instance = it } }
    }
}

/** 兼容现有配置编码，编辑事务统一交给 M3X 异步保存。 */
internal class StoredPreferences(val store: MutableStore<Map<String, String>>) {
    fun getString(key: String, fallback: String?): String? = store.value[key] ?: fallback
    fun getBoolean(key: String, fallback: Boolean): Boolean = store.value[key]?.toBooleanStrictOrNull() ?: fallback
    fun edit(): Editor = Editor()
    inner class Editor {
        private val changes = mutableMapOf<String, String?>()
        fun putString(key: String, value: String?): Editor = apply { changes[key] = value }
        fun putBoolean(key: String, value: Boolean): Editor = apply { changes[key] = value.toString() }
        fun apply() {
            val updates = changes.toMap()
            store.update { current -> current.toMutableMap().apply { updates.forEach { (key, value) -> if (value == null) remove(key) else put(key, value) } } }
        }
    }
}

private object StringMapSerializer : Serializer<Map<String, String>> {
    override val defaultValue: Map<String, String> = emptyMap()
    override suspend fun readFrom(input: InputStream): Map<String, String> {
        try {
            val json = JSONObject(input.readBytes().toString(Charsets.UTF_8))
            return json.keys().asSequence().associateWith { json.getString(it) }
        } catch (error: org.json.JSONException) {
            throw CorruptionException("HallPad 设置文件格式错误", error)
        }
    }
    override suspend fun writeTo(t: Map<String, String>, output: OutputStream) { output.write(JSONObject(t).toString().toByteArray(Charsets.UTF_8)) }
}
