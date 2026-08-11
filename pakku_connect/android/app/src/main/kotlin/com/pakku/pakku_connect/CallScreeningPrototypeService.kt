package com.pakku.pakku_connect

import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log

class CallScreeningPrototypeService : CallScreeningService() {

    override fun onScreenCall(callDetails: Call.Details) {
        val timestamp = System.currentTimeMillis()
        Log.d(TAG, "INSTRUMENTATION-DEEP [$timestamp]: CallScreeningPrototypeService.onScreenCall() invoked.")
        
        val handle = callDetails.handle?.schemeSpecificPart
        Log.d(TAG, "INSTRUMENTATION-DEEP [$timestamp]: CallScreeningPrototypeService Call.Details.handle: [REDACTED]")
        Log.d(TAG, "INSTRUMENTATION-DEEP [$timestamp]: CallScreeningPrototypeService Call Received")

        // Pass the number to PhoneStateService so it can use it when the broadcast arrives
        if (handle != null) {
            PhoneStateService.latestScreenedNumber = handle
        }

        // Immediately return empty response to allow the call without delaying or modifying it
        val response = CallResponse.Builder().build()
        respondToCall(callDetails, response)
        
        Log.d(TAG, "INSTRUMENTATION-DEEP [$timestamp]: CallScreeningPrototypeService respondToCall completed.")
    }

    companion object {
        private const val TAG = "CallScreeningProto"
    }
}
