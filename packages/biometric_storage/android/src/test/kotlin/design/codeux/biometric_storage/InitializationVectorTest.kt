package design.codeux.biometric_storage

import java.io.EOFException
import java.io.File
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class InitializationVectorTest {
    private lateinit var file: File

    @Before
    fun createFile() {
        file = File.createTempFile("biometric_iv", ".v2.txt")
    }

    @After
    fun deleteFile() {
        file.delete()
    }

    @Test
    fun readsTheIvInFrontOfTheCiphertext() {
        val iv = ByteArray(12) { (it + 1).toByte() }
        file.writeBytes(iv + ByteArray(20) { 0x7f })

        assertArrayEquals(iv, readInitializationVector(file, 12))
    }

    @Test
    fun rejectsATruncatedIv() {
        file.writeBytes(ByteArray(5))

        assertThrows(EOFException::class.java) { readInitializationVector(file, 12) }
    }

    @Test
    fun closesTheStreamAfterEveryRead() {
        file.writeBytes(ByteArray(32))
        repeat(200) { readInitializationVector(file, 12) }
        file.writeBytes(ByteArray(3))
        repeat(200) {
            assertThrows(EOFException::class.java) { readInitializationVector(file, 12) }
        }

        // Windows refuses to delete a file while a stream still holds it open;
        // other hosts only cover the read and error paths here.
        assertTrue(file.delete())
    }
}
