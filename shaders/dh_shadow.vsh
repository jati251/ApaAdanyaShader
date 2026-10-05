#version 330 compatibility

void main() {
    // Clip Distant Horizons LODs from shadow pass entirely to save massive shadow draw overhead
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
}
