package com.connecto.app

import android.telecom.Call
import android.telecom.CallScreeningService

class CallScreeningPrototypeService : CallScreeningService() {

    override fun onScreenCall(callDetails: Call.Details) {
        val handle = callDetails.handle?.schemeSpecificPart

        // Pass the number to PhoneStateService so it can use it when the broadcast arrives
        if (handle != null) {
            PhoneStateService.latestScreenedNumber = handle
        }

        // Immediately return empty response to allow the call without delaying or modifying it
        val response = CallResponse.Builder().build()
        respondToCall(callDetails, response)
    }

    companion object {
        private const val TAG = "CallScreeningProto"
    }
}
