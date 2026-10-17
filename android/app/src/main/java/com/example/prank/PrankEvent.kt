package com.example.prank
sealed class PrankEvent {
    data class Shown(val payloadId: String) : PrankEvent()
    data class Hidden(val payloadId: String, val reason: String) : PrankEvent()
    data class Action(val payloadId: String, val action: String) : PrankEvent()
    data class Error(val code: String, val message: String) : PrankEvent()
}
