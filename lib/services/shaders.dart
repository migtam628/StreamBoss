/// A libmpv user shader (mpv `//!HOOK` GLSL). Built-ins ship with the app;
/// custom ones are pasted in by the user and stored in preferences.
class ShaderDef {
  final String id;
  final String name;
  final String description;
  final String source;
  final bool builtin;

  const ShaderDef({
    required this.id,
    required this.name,
    required this.source,
    this.description = '',
    this.builtin = false,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'desc': description, 'src': source};

  factory ShaderDef.fromJson(Map<String, dynamic> j) => ShaderDef(
        id: j['id'] as String,
        name: j['name'] as String,
        description: (j['desc'] as String?) ?? '',
        source: j['src'] as String,
      );
}

const builtinShaders = <ShaderDef>[
  ShaderDef(
    id: 'sharpen',
    name: 'Sharpen',
    description: 'Mild luma unsharp mask for soft streams',
    builtin: true,
    source: r'''
//!DESC StreamBoss Sharpen
//!HOOK LUMA
//!BIND HOOKED

#define STRENGTH 0.6

vec4 hook() {
    vec4 c = HOOKED_texOff(vec2(0.0, 0.0));
    float n = HOOKED_texOff(vec2(0.0, -1.0)).x;
    float s = HOOKED_texOff(vec2(0.0, 1.0)).x;
    float e = HOOKED_texOff(vec2(1.0, 0.0)).x;
    float w = HOOKED_texOff(vec2(-1.0, 0.0)).x;
    float blur = (n + s + e + w) * 0.25;
    c.x = clamp(c.x + (c.x - blur) * STRENGTH, 0.0, 1.0);
    return c;
}
''',
  ),
  ShaderDef(
    id: 'vibrance',
    name: 'Vibrance',
    description: 'Boost color saturation a little',
    builtin: true,
    source: r'''
//!DESC StreamBoss Vibrance
//!HOOK OUTPUT
//!BIND HOOKED

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    c.rgb = mix(vec3(l), c.rgb, 1.25);
    return c;
}
''',
  ),
  ShaderDef(
    id: 'warm',
    name: 'Night warm',
    description: 'Warmer color temperature for late viewing',
    builtin: true,
    source: r'''
//!DESC StreamBoss Night warm
//!HOOK OUTPUT
//!BIND HOOKED

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    c.rgb *= vec3(1.0, 0.92, 0.78);
    return c;
}
''',
  ),
  ShaderDef(
    id: 'grain',
    name: 'Film grain',
    description: 'Subtle animated grain that hides banding',
    builtin: true,
    source: r'''
//!DESC StreamBoss Film grain
//!HOOK OUTPUT
//!BIND HOOKED

float rnd(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    float g = rnd(HOOKED_pos * HOOKED_size + float(frame)) - 0.5;
    c.rgb += g * 0.04;
    return c;
}
''',
  ),
];

/// Shader ids in pipeline order. Unknown ids are dropped; shaders missing from
/// [saved] are appended so newly added ones always show up.
List<String> reconcileOrder(List<String> saved, Iterable<ShaderDef> all) {
  final known = all.map((e) => e.id).toSet();
  final out = [for (final id in saved) if (known.contains(id)) id];
  for (final s in all) {
    if (!out.contains(s.id)) out.add(s.id);
  }
  return out;
}
