package com.timhxl.hallbeat

import kotlinx.coroutines.delay
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow

internal class SdCardController(private val exchange:suspend(ByteArray)->ByteArray) {
    data class Ui(val busy:Boolean=false,val done:Int=0,val total:Int=0,val message:String="",val files:List<SdFat32.Entry> = emptyList())
    val state=MutableStateFlow(Ui());private val mutex=Mutex()
    private suspend fun op(payload:ByteArray):ByteArray { val reply=exchange(payload);require(reply.size==36 && reply[0]==payload[0]);check(reply[1].toInt()==0){when(reply[1].toInt() and 255){5->"请先退出设备脱机演奏，再管理 SD 卡";10->"SD 卡读写失败";7->"固件不支持 SD 下载";else->"SD 命令失败：${reply[1].toInt() and 255}"}};return reply }
    private suspend fun lockCard() {
        repeat(6) { attempt ->
            val reply=exchange(byteArrayOf(0));require(reply.size==36 && reply[0]==0.toByte())
            if(reply[1]==0.toByte())return
            if(reply[1].toInt()!=5 || attempt==5)error("请先停止设备曲目加载/演奏；目录预读结束后可重试")
            delay(200)
        }
    }
    private fun word(op:Int,n:Long)=byteArrayOf(op.toByte(),n.toByte(),(n shr 8).toByte(),(n shr 16).toByte(),(n shr 24).toByte())
    private suspend fun read(lba:Long):ByteArray { op(word(2,lba));val bytes=ByteArray(512);for(offset in 0 until 512 step 32){val b=op(byteArrayOf(5,offset.toByte(),(offset shr 8).toByte()));b.copyInto(bytes,offset,4,36)};return bytes }
    private suspend fun write(lba:Long,bytes:ByteArray) { require(bytes.size==512);for(offset in 0 until 512 step 192){op(byteArrayOf(3,offset.toByte(),(offset shr 8).toByte())+bytes.copyOfRange(offset,minOf(512,offset+192)))};op(word(4,lba)) }
    private suspend fun <T> card(action:suspend(SdFat32)->T):T = mutex.withLock {
        state.value=state.value.copy(busy=true,done=0,total=0,message="正在访问 SD 卡…")
        var locked=false
        try { lockCard();locked=true;val fs=SdFat32(::read,::write);fs.mount();val result=action(fs);state.value=state.value.copy(files=fs.list().filter{it.name.endsWith(".HPG")},message="完成");result }
        catch(e:Exception){state.value=state.value.copy(message=e.message?:"操作已取消");throw e}
        finally { if(locked)withContext(NonCancellable){runCatching{op(byteArrayOf(1))}};state.value=state.value.copy(busy=false) }
    }
    suspend fun refresh(){card{}}
    suspend fun delete(file:SdFat32.Entry){card{fs->fs.delete(file)}}
    suspend fun upload(name:String,bytes:ByteArray,replace:Boolean){card{fs->fs.upload(name,bytes,replace){d,t->state.value=state.value.copy(done=d,total=t,message="下载并校验 ${d*100L/t}%")}}}
}
