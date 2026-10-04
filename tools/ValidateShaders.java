import java.nio.file.*;
import java.util.*;
import java.util.regex.*;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL20.*;

// Compile and link on the local OpenGL driver without opening a visible window.
// Iris runtime validation is still required for framebuffer bindings and options.
class ValidateShaders {
    static Path root;
    static String profile;
    static String expand(Path file, Set<Path> stack) throws Exception {
        file=file.toAbsolutePath().normalize();
        if(!file.startsWith(root)) throw new Exception("Include outside shader root: "+file);
        if(!stack.add(file)) throw new Exception("Include cycle: "+file);
        StringBuilder out=new StringBuilder();
        for(String line:Files.readAllLines(file)) {
            Matcher m=Pattern.compile("^\\s*#include \"([^\"]+)\".*").matcher(line);
            if(m.matches()) {
                String include=m.group(1);
                out.append(expand(include.startsWith("/")?root.resolve(include.substring(1)):file.getParent().resolve(include),stack));
            } else out.append(line).append('\n');
        }
        stack.remove(file); return out.toString();
    }
    static int compile(Path file,int type) throws Exception {
        String source=expand(file,new HashSet<>());
        if(profile.equals("BALANCED")) {
            source=source.replace("#define SSGI\n","//#define SSGI\n").replace("#define VOLUMETRIC_LIGHT\n","//#define VOLUMETRIC_LIGHT\n");
            source=source.replace("#define SSR_STEPS 48","#define SSR_STEPS 24").replace("#define GI_SAMPLES 4","#define GI_SAMPLES 2").replace("#define CLOUD_STEPS 20","#define CLOUD_STEPS 12").replace("#define SHADOW_SAMPLES 12","#define SHADOW_SAMPLES 4");
        }
        if(profile.equals("ULTRA")) source=source.replace("#define SSR_STEPS 48","#define SSR_STEPS 96").replace("#define GI_SAMPLES 4","#define GI_SAMPLES 8").replace("#define CLOUD_STEPS 20","#define CLOUD_STEPS 36").replace("#define SHADOW_SAMPLES 12","#define SHADOW_SAMPLES 16");
        if(profile.equals("NORMALS")) source=source.replace("//#define RESOURCE_NORMALS","#define RESOURCE_NORMALS");
        if(profile.equals("MINIMAL")) for(String option:List.of("CLOUD_SHADOWS","SSR","SSGI","VOLUMETRIC_CLOUDS","VOLUMETRIC_LIGHT","BLOOM","FXAA","WAVING_FOLIAGE")) source=source.replace("#define "+option+"\n","//#define "+option+"\n");
        int shader=glCreateShader(type); glShaderSource(shader,source); glCompileShader(shader);
        if(glGetShaderi(shader,GL_COMPILE_STATUS)==0) throw new Exception(profile+" "+file+"\n"+glGetShaderInfoLog(shader));
        return shader;
    }
    public static void main(String[] args) throws Exception {
        root=Path.of(args[0]).toAbsolutePath().normalize();
        if(!GLFW.glfwInit()) throw new Exception("GLFW failed");
        GLFW.glfwWindowHint(GLFW.GLFW_VISIBLE,GLFW.GLFW_FALSE);
        GLFW.glfwWindowHint(GLFW.GLFW_CONTEXT_VERSION_MAJOR,3);
        GLFW.glfwWindowHint(GLFW.GLFW_CONTEXT_VERSION_MINOR,3);
        GLFW.glfwWindowHint(GLFW.GLFW_OPENGL_PROFILE,GLFW.GLFW_OPENGL_COMPAT_PROFILE);
        long window=GLFW.glfwCreateWindow(32,32,"Shader validation",0,0);
        if(window==0) throw new Exception("OpenGL context failed");
        GLFW.glfwMakeContextCurrent(window); GL.createCapabilities();
        System.out.println("GPU: "+glGetString(GL_RENDERER));
        int count=0;
        try {
            for(String variant:List.of("BALANCED","HIGH","ULTRA","NORMALS","MINIMAL")) {
                profile=variant; int passCount=0;
                for(String folder:List.of("","world-1","world1")) {
                    try(var files=Files.list(root.resolve(folder))) {
                        for(Path vertex:files.filter(p->p.toString().endsWith(".vsh")).toList()) {
                            Path fragment=vertex.resolveSibling(vertex.getFileName().toString().replace(".vsh",".fsh"));
                            int vs=compile(vertex,GL_VERTEX_SHADER),fs=compile(fragment,GL_FRAGMENT_SHADER);
                            int program=glCreateProgram(); glAttachShader(program,vs); glAttachShader(program,fs); glLinkProgram(program);
                            if(glGetProgrami(program,GL_LINK_STATUS)==0) throw new Exception(variant+" "+vertex+"\n"+glGetProgramInfoLog(program));
                            glDeleteProgram(program); glDeleteShader(vs); glDeleteShader(fs); count++; passCount++;
                        }
                    }
                }
                System.out.println(variant+": "+passCount+" programs compiled and linked");
            }
            System.out.println("PASS: "+count+" program variants");
        } finally { GLFW.glfwDestroyWindow(window); GLFW.glfwTerminate(); }
    }
}

