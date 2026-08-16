import re

file_path = "/Users/prakashbiswas/Personal Projects/paku connect/Connecto/apps/connecto_app/android/app/src/main/kotlin/com/connecto/app/FileTransferService.kt"

with open(file_path, "r") as f:
    content = f.read()

# Add imports for Mutex
imports = """import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
"""
content = re.sub(r'import kotlinx.coroutines.launch\n', r'import kotlinx.coroutines.launch\n' + imports, content)

# Add Mutex and pending transfers count
declarations = """    private val transferMutex = Mutex()
    private var pendingTransfers = 0
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())"""
content = re.sub(r'    private val serviceScope = CoroutineScope\(Dispatchers.IO \+ SupervisorJob\(\)\)', declarations, content)

# Update onStartCommand
old_onstart = """        if (uri != null && type != null) {
            // Reset state for new transfer in case Android pools this Service instance
            Log.d("FileTransfer", "[PHASE7] RESETTING transferResultReported to FALSE")
            transferResultReported = false
            
            serviceScope.launch {
                handleTransfer(uri, type, batchId, batchCount, batchIndex, batchTotal, isBatchedZip)
            }
        } else {
            stopSelf()
        }"""

new_onstart = """        if (uri != null && type != null) {
            pendingTransfers++
            serviceScope.launch {
                try {
                    transferMutex.withLock {
                        Log.d("FileTransfer", "[PHASE8] STARTING queued transfer")
                        transferResultReported = false
                        handleTransfer(uri, type, batchId, batchCount, batchIndex, batchTotal, isBatchedZip)
                    }
                } finally {
                    pendingTransfers--
                    if (pendingTransfers <= 0) {
                        Log.d("FileTransfer", "[PHASE8] All transfers complete, stopping service")
                        stopSelf()
                    }
                }
            }
        } else {
            if (pendingTransfers <= 0) {
                stopSelf()
            }
        }"""
content = content.replace(old_onstart, new_onstart)

# Update handleTransfer to remove isTransferring check
old_handle_start = """    private suspend fun handleTransfer(uri: Uri, mimeType: String, batchId: String?, batchCount: Int?, batchIndex: Int?, batchTotal: Int?, isBatchedZip: Boolean) {
        if (isTransferring) return // Only 1 concurrent transfer supported
        isTransferring = true
        currentTransferId = UUID.randomUUID().toString()"""

new_handle_start = """    private suspend fun handleTransfer(uri: Uri, mimeType: String, batchId: String?, batchCount: Int?, batchIndex: Int?, batchTotal: Int?, isBatchedZip: Boolean) {
        currentTransferId = UUID.randomUUID().toString()"""
content = content.replace(old_handle_start, new_handle_start)

# Update cleanupAndStop to NOT stopSelf or cancelChildren
old_cleanup = """        transport.stopListening()
        serviceScope.coroutineContext.cancelChildren()
        
        currentTransferId?.let { id ->"""

new_cleanup = """        transport.stopListening()
        
        // Cancel jobs for THIS transfer only, do not cancel the whole scope
        readyJob?.cancel()
        ackJob?.cancel()
        completeJob?.cancel()
        
        currentTransferId?.let { id ->"""
content = content.replace(old_cleanup, new_cleanup)

old_cleanup2 = """        isTransferring = false
        currentTransferId = null
        
        Log.d("FileTransfer", "[PHASE7] STOP SELF CALLED")

        stopSelf()"""

new_cleanup2 = """        currentTransferId = null
        Log.d("FileTransfer", "[PHASE8] cleanupAndStop finished for transfer")"""
content = content.replace(old_cleanup2, new_cleanup2)


with open(file_path, "w") as f:
    f.write(content)

print("Patched FileTransferService.kt")
