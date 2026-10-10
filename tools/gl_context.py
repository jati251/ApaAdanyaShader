"""Native driver context: CGL on macOS; a hidden GLFW window elsewhere."""
import ctypes as c
import sys


class GLContext:
    def __init__(self):
        self.functions = {}
        if sys.platform == 'darwin':
            self.version = '410'
            self.library = c.CDLL('/System/Library/Frameworks/OpenGL.framework/OpenGL')
            pixel, self.context, count = c.c_void_p(), c.c_void_p(), c.c_int()
            choose = self.bind('CGLChoosePixelFormat', c.c_int, c.POINTER(c.c_int), c.POINTER(c.c_void_p), c.POINTER(c.c_int))
            create = self.bind('CGLCreateContext', c.c_int, c.c_void_p, c.c_void_p, c.POINTER(c.c_void_p))
            assert choose((c.c_int * 5)(99, 0x3200, 73, 0, 0), c.byref(pixel), c.byref(count)) == 0
            assert create(pixel, None, c.byref(self.context)) == 0
            self.bind('CGLDestroyPixelFormat', c.c_int, c.c_void_p)(pixel)
            assert self.bind('CGLSetCurrentContext', c.c_int, c.c_void_p)(self.context) == 0
        else:
            self.version = '330'
            try:
                import glfw
            except ImportError:
                raise SystemExit('GPU validation needs GLFW: python -m pip install glfw\nOr run with --static for configuration checks.')
            self.glfw = glfw
            if not glfw.init():
                raise SystemExit('GLFW could not initialize the display/OpenGL driver.')
            glfw.window_hint(glfw.VISIBLE, glfw.FALSE)
            advanced='--advanced' in sys.argv
            glfw.window_hint(glfw.CONTEXT_VERSION_MAJOR, 4 if advanced else 3)
            glfw.window_hint(glfw.CONTEXT_VERSION_MINOR, 3)
            glfw.window_hint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
            self.window = glfw.create_window(32, 32, 'Shader validation', None, None)
            if not self.window:
                glfw.terminate()
                raise SystemExit('The driver could not create an OpenGL 3.3 core context.')
            glfw.make_context_current(self.window)

    def bind(self, name, restype, *argtypes):
        if hasattr(self, 'library'):
            fn = getattr(self.library, name)
            fn.restype, fn.argtypes = restype, argtypes
        else:
            address = self.glfw.get_proc_address(name)
            if not address:
                raise RuntimeError(f'OpenGL driver does not expose {name}')
            convention = c.WINFUNCTYPE if sys.platform == 'win32' else c.CFUNCTYPE
            fn = convention(restype, *argtypes)(address)
        self.functions[name] = fn
        return fn

    def close(self):
        if hasattr(self, 'library'):
            self.bind('CGLSetCurrentContext', c.c_int, c.c_void_p)(None)
            self.bind('CGLDestroyContext', c.c_int, c.c_void_p)(self.context)
        else:
            self.glfw.destroy_window(self.window)
            self.glfw.terminate()
