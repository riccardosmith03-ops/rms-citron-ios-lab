/* SPDX-License-Identifier: MIT
 * Original bounded display/input/audio smoke. SOURCE ONLY: not built or run.
 */
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <switch.h>

#define BUILD_ID "rms-citron-audio-smoke-20261101-v1"
#define EXPECTED_CHECKSUM UINT32_C(0x5acd3dc5)
#define AUDIO_RATE 48000u
#define AUDIO_CHANNELS 2u
#define BUFFER_FRAMES 4800u
#define BUFFER_BYTES 0x5000u
#define AUDIO_BUFFERS 2u
#define TONE_FRAMES 24000u
#define TONE_PERIOD 48u
#define RAMP_FRAMES 48u
#define TONE_AMPLITUDE 2048

/* Strong unmangled C symbol. A loader heap override can still take precedence. */
size_t __nx_heap_size = 0x04000000;

/* Each row is page aligned because its stride is also a multiple of 0x1000. */
_Alignas(0x1000) static int16_t pcm[AUDIO_BUFFERS][BUFFER_BYTES / sizeof(int16_t)];
static AudioOutBuffer buffers[AUDIO_BUFFERS];
_Static_assert(BUFFER_BYTES % 0x1000 == 0, "audout buffer stride alignment");
_Static_assert(BUFFER_FRAMES * AUDIO_CHANNELS * sizeof(int16_t) <= BUFFER_BYTES,
               "PCM payload fits the padded buffer");
_Static_assert(TONE_FRAMES == AUDIO_RATE / 2, "finite 500ms pulse");

static struct {
    bool initialized, started, failed, has_result, flush_attempted, flushed;
    bool queued[AUDIO_BUFFERS];
    const char *first_error;
    Result first_result, stop_result, flush_result, drain_result;
    u32 sample_rate, channels, remaining_tone_frames, generated_tone_frames;
    PcmFormat format;
    unsigned phase, unreleased_at_close;
    uint64_t appended_buffers, released_buffers;
} audio;

static void audio_problem(const char *operation, Result result, bool has_result) {
    if (audio.failed) return; /* Preserve the first cause. */
    audio.failed = true;
    audio.first_error = operation;
    audio.first_result = result;
    audio.has_result = has_result;
}

/* Never modifies a buffer still owned by audout. No dynamic PCM allocation. */
static bool fill_free_buffer(unsigned index) {
    if (index >= AUDIO_BUFFERS || audio.queued[index]) {
        audio_problem("attempt to modify a queued buffer", 0, false);
        return false;
    }
    memset(pcm[index], 0, sizeof(pcm[index])); /* Also zero the padding. */
    for (u32 frame = 0; frame < BUFFER_FRAMES; ++frame) {
        int sample = 0;
        if (audio.remaining_tone_frames != 0) {
            int amplitude = TONE_AMPLITUDE;
            if (audio.generated_tone_frames < RAMP_FRAMES)
                amplitude = amplitude * (int)(audio.generated_tone_frames + 1) / RAMP_FRAMES;
            if (audio.remaining_tone_frames <= RAMP_FRAMES)
                amplitude = amplitude * (int)(audio.remaining_tone_frames - 1) / RAMP_FRAMES;
            sample = audio.phase < TONE_PERIOD / 2 ? amplitude : -amplitude;
            audio.phase = (audio.phase + 1) % TONE_PERIOD;
            --audio.remaining_tone_frames;
            ++audio.generated_tone_frames;
        }
        pcm[index][frame * AUDIO_CHANNELS] = (int16_t)sample;
        pcm[index][frame * AUDIO_CHANNELS + 1] = (int16_t)sample;
    }
    armDCacheFlush(pcm[index], sizeof(pcm[index]));
    return true;
}

static bool append_free_buffer(unsigned index) {
    if (!fill_free_buffer(index)) return false;
    Result result = audoutAppendAudioOutBuffer(&buffers[index]);
    if (R_FAILED(result)) {
        audio_problem("audoutAppendAudioOutBuffer", result, true);
        return false;
    }
    audio.queued[index] = true;
    ++audio.appended_buffers;
    return true;
}

/* The pinned wrapper provides space for one returned descriptor pointer. */
static bool take_released_buffer(AudioOutBuffer *released, u32 count, unsigned *index) {
    if (count != 1 || released == NULL) {
        audio_problem("unexpected released-buffer count/pointer", 0, false);
        return false;
    }
    for (unsigned i = 0; i < AUDIO_BUFFERS; ++i) {
        if (released != &buffers[i]) continue;
        if (!audio.queued[i]) {
            audio_problem("duplicate buffer release", 0, false);
            return false;
        }
        audio.queued[i] = false;
        ++audio.released_buffers;
        *index = i;
        return true;
    }
    audio_problem("unknown released descriptor; not dereferenced", 0, false);
    return false;
}

static void audio_open(void) {
    Result result = audoutInitialize();
    if (R_FAILED(result)) {
        /* libnx's service guard already cleans a failed initialization. */
        audio_problem("audoutInitialize", result, true);
        return;
    }
    audio.initialized = true;
    audio.sample_rate = audoutGetSampleRate();
    audio.channels = audoutGetChannelCount();
    audio.format = audoutGetPcmFormat();
    if (audio.sample_rate != AUDIO_RATE || audio.channels != AUDIO_CHANNELS ||
        audio.format != PcmFormat_Int16) {
        audio_problem("negotiated format is not stereo Int16/48000Hz", 0, false);
        return;
    }
    for (unsigned i = 0; i < AUDIO_BUFFERS; ++i) {
        if ((uintptr_t)pcm[i] % 0x1000 != 0) {
            audio_problem("PCM address alignment", 0, false);
            return;
        }
        buffers[i].next = NULL;
        buffers[i].buffer = pcm[i];
        buffers[i].buffer_size = sizeof(pcm[i]);
        buffers[i].data_size = BUFFER_FRAMES * AUDIO_CHANNELS * sizeof(int16_t);
        buffers[i].data_offset = 0;
        if (!append_free_buffer(i)) return;
    }
    result = audoutStartAudioOut();
    if (R_FAILED(result)) {
        audio_problem("audoutStartAudioOut", result, true);
        return;
    }
    audio.started = true;
}

static void audio_poll(void) {
    if (!audio.started || audio.failed) return;
    /* At most two non-waiting IPC requests per UI iteration; no infinite wait. */
    for (unsigned n = 0; n < AUDIO_BUFFERS; ++n) {
        AudioOutBuffer *released = NULL;
        u32 count = 0;
        Result result = audoutGetReleasedAudioOutBuffer(&released, &count);
        if (R_FAILED(result)) {
            audio_problem("audoutGetReleasedAudioOutBuffer", result, true);
            return;
        }
        if (count == 0) return;
        unsigned index = 0;
        if (!take_released_buffer(released, count, &index)) return;
        if (!append_free_buffer(index)) return;
    }
}

static void audio_close(void) {
    if (!audio.initialized) return;
    audio.remaining_tone_frames = 0;
    audio.stop_result = audoutStopAudioOut();
    if (R_FAILED(audio.stop_result))
        audio_problem("audoutStopAudioOut during cleanup", audio.stop_result, true);
    /* Optional versioned flush: report its Result, never spin/retry forever. */
    if (hosversionAtLeast(4, 0, 0)) {
        audio.flush_attempted = true;
        audio.flush_result = audoutFlushAudioOutBuffers(&audio.flushed);
        if (R_FAILED(audio.flush_result))
            audio_problem("audoutFlushAudioOutBuffers during cleanup", audio.flush_result, true);
    }
    for (unsigned n = 0; n < AUDIO_BUFFERS * 2; ++n) {
        AudioOutBuffer *released = NULL;
        u32 count = 0;
        audio.drain_result = audoutGetReleasedAudioOutBuffer(&released, &count);
        if (R_FAILED(audio.drain_result)) {
            audio_problem("audio release during cleanup", audio.drain_result, true);
            break;
        }
        if (count == 0) break;
        unsigned index = 0;
        if (!take_released_buffer(released, count, &index)) break;
    }
    for (unsigned i = 0; i < AUDIO_BUFFERS; ++i)
        if (audio.queued[i]) ++audio.unreleased_at_close;
    /* Session handles close before exit. Static storage is never freed/reused. */
    audoutExit();
    audio.initialized = false;
    audio.started = false;
}

extern void __nx_win_init(void);
extern void __nx_win_exit(void);
static void require_service(Result result) {
    if (R_FAILED(result)) diagAbortWithResult(result);
}
void __appInit(void) {
    require_service(smInitialize());
    if (hosversionGet() == 0 && R_SUCCEEDED(setsysInitialize())) {
        SetSysFirmwareVersion firmware;
        Result queried = setsysGetFirmwareVersion(&firmware);
        setsysExit();
        if (R_SUCCEEDED(queried))
            hosversionSet(MAKEHOSVERSION(firmware.major, firmware.minor, firmware.micro));
    }
    require_service(appletInitialize());
    require_service(hidInitialize());
    __nx_win_init();
}
void __appExit(void) {
    audio_close(); /* Idempotent if main already closed it. */
    __nx_win_exit();
    hidExit();
    appletExit();
    smExit();
}

static uint32_t checksum(const volatile uint8_t *data, size_t size) {
    uint32_t value = UINT32_C(2166136261);
    for (size_t i = 0; i < size; ++i)
        value = (value ^ data[i]) * UINT32_C(16777619);
    return value;
}

int main(void) {
    static volatile uint8_t data[4096];
    for (size_t i = 0; i < sizeof(data); ++i) data[i] = (uint8_t)((i * 37u + 11u) & 255u);
    if (consoleInit(NULL) == NULL) return 2;
    padConfigureInput(1, HidNpadStyleSet_NpadStandard);
    PadState pad;
    padInitializeDefault(&pad);
    uint64_t iterations = 0;
    uint32_t presses = 0;
    const unsigned colors[] = {36, 35, 33};
    printf("\x1b[2J\x1b[1;1H%s\n", BUILD_ID);
    printf("Heap richiesto64MiB; nessun FS/SD/rete/account/microfono\n");
    printf("A: contatore/colore + tono500ms; B: silenzio; Plus: esci\n");
    printf("Il tono passa da audout:u emulato, non da un beep iOS.\n");
    audio_open();
    if (audio.failed) audio_close();
    while (appletMainLoop()) {
        padUpdate(&pad);
        const u64 down = padGetButtonsDown(&pad);
        if (down & HidNpadButton_Plus) break;
        if (down & HidNpadButton_A) {
            ++presses;
            if (audio.started && !audio.failed) {
                audio.remaining_tone_frames = TONE_FRAMES;
                audio.generated_tone_frames = 0;
                audio.phase = 0;
            }
        }
        if (down & HidNpadButton_B) audio.remaining_tone_frames = 0;
        audio_poll();
        if (audio.failed) audio_close();
        const uint32_t actual = checksum(data, sizeof(data));
        printf("\x1b[6;1H\x1b[%umIterazioni: %020" PRIu64 "\x1b[0m\x1b[K\n",
               colors[presses % 3u], iterations++);
        printf("Pressioni A: %010" PRIu32 "\x1b[K\n", presses);
        printf("FNV1a: %08" PRIx32 " atteso:%08" PRIx32 " %s\x1b[K\n",
               actual, EXPECTED_CHECKSUM, actual == EXPECTED_CHECKSUM ? "PASS" : "FAIL");
        printf("Audio %" PRIu32 "Hz/%" PRIu32 "ch format%u; avviato:%d\x1b[K\n",
               audio.sample_rate, audio.channels, (unsigned)audio.format, audio.started);
        printf("Accodati:%" PRIu64 " rilasciati:%" PRIu64 "\x1b[K\n",
               audio.appended_buffers, audio.released_buffers);
        printf("Frame tono ancora da accodare:%" PRIu32 " (NON stato udibile)\x1b[K\n",
               audio.remaining_tone_frames);
        printf("Errore:%s\x1b[K\n", audio.failed ? audio.first_error : "nessuno rilevato");
        printf("Result API valido:%d codice:%08" PRIx32 "\x1b[K\n",
               audio.has_result, (uint32_t)audio.first_result);
        printf("Stop:%08" PRIx32 " flush tentato:%d rc:%08" PRIx32 "\x1b[K\n",
               (uint32_t)audio.stop_result, audio.flush_attempted, (uint32_t)audio.flush_result);
        printf("Contatore NON FPS; udibilita da confermare; coda fino a200ms.\x1b[K\n");
        consoleUpdate(NULL);
    }
    audio_close();
    printf("\x1b[17;1HChiusura: stop=%08" PRIx32 " drain=%08" PRIx32
           " non-rilasciati prima exit=%u\x1b[K\n",
           (uint32_t)audio.stop_result, (uint32_t)audio.drain_result, audio.unreleased_at_close);
    consoleUpdate(NULL);
    consoleExit(NULL);
    return audio.failed ? 1 : 0;
}
