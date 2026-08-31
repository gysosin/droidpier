# Decoder fixture

`gray-16x16.h264` is one synthetic gray H.264 frame, created for the packaging
smoke check. It contains no device capture or personal data. The test decodes it
to exactly 1024 bytes of RGBA using the actual bundled decoder.
