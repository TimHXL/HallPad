package com.hallpad.verification
import java.io.File
fun main(args:Array<String>){val atlas=File(args[0]).readBytes();File(args[1]).readLines().forEach{val p=it.split('\t');val result=Hpg3Encoder.encode(File(p[0]).readBytes(),p[1],atlas,p[3].toInt());File(p[2]).writeBytes(result.bytes)};println("PASS Kotlin batch conversion")}
