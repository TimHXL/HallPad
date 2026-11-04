package com.timhxl.hallbeat

import androidx.compose.runtime.*
import androidx.compose.material3.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import androidx.compose.ui.platform.LocalContext
import java.util.zip.CRC32

@Composable
internal fun SdCardDialog(controller:SdCardController,midi:ByteArray,title:String,demo:Boolean,onClose:()->Unit) {
    val ui by controller.state.collectAsState();val scope=rememberCoroutineScope();val context=LocalContext.current
    var name by remember{mutableStateOf("S%07X.HPG".format(CRC32().apply{update(midi);update(title.toByteArray())}.value and 0x0fffffff))}
    var titleText by remember{mutableStateOf(Hpg3Encoder.codePoints(title).take(32).joinToString(""){String(Character.toChars(it))})}
    var message by remember{mutableStateOf("")};var job by remember{mutableStateOf<Job?>(null)};var output by remember{mutableStateOf<Hpg3Encoder.Output?>(null)};var preparing by remember{mutableStateOf(false)}
    var overwrite by remember{mutableStateOf(false)};var delete by remember{mutableStateOf<SdFat32.Entry?>(null)}
    val busy=ui.busy || preparing
    fun transfer(replace:Boolean){job=scope.launch { try { preparing=true;val generated=withContext(Dispatchers.Default){Hpg3Encoder.encode(midi,titleText,context.assets.open("hpg/title22.hga").use{it.readBytes()})};output=generated;preparing=false;controller.upload(name,generated.bytes,replace);message="已保存到 SD 卡；跳过 ${generated.skipped} 个无法演奏的音符" }catch(e:CancellationException){message="已取消；再次下载同名文件可继续"}catch(e:Exception){message=e.message?:"失败"}finally{preparing=false} } }
    LaunchedEffect(controller){job=scope.launch{runCatching{controller.refresh()}.onFailure{message=it.message?:"读取失败"}}}
    AlertDialog(onDismissRequest={if(!busy)onClose()},title={Text(if (demo) "演示 SD 卡离线曲库" else "SD 卡离线曲库")},text={Column(Modifier.heightIn(max=520.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)){
        Text(if (demo) "演示模式。曲谱写入本次运行的模拟 SD 卡。" else "转换全部音轨，保留独立音轨和合并音轨。设备须退出脱机演奏后才能写卡。")
        OutlinedTextField(titleText,{titleText=it},label={Text("曲目名称（最多32字）")},enabled=!busy)
        OutlinedTextField(name,{name=it.uppercase()},label={Text("卡内文件名（8.3）")},enabled=!busy)
        if(busy){Text(if(preparing)"正在生成 HPG…" else ui.message);if(ui.total>0)Text("${ui.done} / ${ui.total} 字节")}
        Text(message.ifBlank{ui.message});output?.let{Text("${it.tracks} 个音轨选项，${it.bytes.size} 字节")}
        Row{TextButton(enabled=!busy,onClick={job=scope.launch{runCatching{controller.refresh()}.onFailure{message=it.message?:"读取失败"}}}){Text("刷新曲库")};TextButton(enabled=!busy,onClick={if(ui.files.any{it.name==name})overwrite=true else transfer(false)}){Text("转换并下载")}}
        Text("卡内曲目 ${ui.files.size}/256")
        ui.files.forEach{file->Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween){Text("${file.name}  ${file.size} B",Modifier.weight(1f));TextButton(enabled=!busy,onClick={delete=file}){Text("删除")}}}
    }},confirmButton={TextButton(onClick={if(busy)job?.cancel() else onClose()}){Text(if(busy)"取消传输" else "关闭")}})
    if(overwrite)AlertDialog(onDismissRequest={overwrite=false},title={Text("覆盖同名曲目？")},text={Text(name)},confirmButton={TextButton(onClick={overwrite=false;transfer(true)}){Text("覆盖")}},dismissButton={TextButton(onClick={overwrite=false}){Text("返回改名")}})
    delete?.let{file->AlertDialog(onDismissRequest={delete=null},title={Text("删除卡内曲目？")},text={Text(file.name)},confirmButton={TextButton(onClick={delete=null;job=scope.launch{runCatching{controller.delete(file)}.onFailure{message=it.message?:"删除失败"}}}){Text("删除")}},dismissButton={TextButton(onClick={delete=null}){Text("取消")}})}
}
