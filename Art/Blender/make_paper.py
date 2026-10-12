"""Create a blank, curved paper model and transparent UI renders in Blender."""
import bpy
import math
import sys
from pathlib import Path
from mathutils import Vector

root = Path(__file__).resolve().parents[2]
output = root / "Sources/DoveSonoArrivato/Resources"
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x = 768
scene.render.resolution_y = 768
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.view_settings.view_transform = 'Standard'
scene.world = bpy.data.worlds.new('Soft studio')
scene.world.use_nodes = True
next(n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND').inputs['Color'].default_value = (0.8, 0.8, 0.8, 1)
next(n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND').inputs['Strength'].default_value = 0.65

# Mostly flat writing area, curled bottom edge, stronger lower-right lift.
size = 80
vertices, faces = [], []
for row in range(size + 1):
    v = row / size
    for col in range(size + 1):
        u = col / size
        bottom = max(0, (0.20 - v) / 0.20)
        corner = max(0, (u - 0.65) / 0.35) * max(0, (0.28 - v) / 0.28)
        z = 0.005 + 0.012 * bottom**3 + 0.095 * corner**3
        vertices.append((u - 0.5 - 0.065 * corner**3, v - 0.5 + 0.045 * corner**3, z))
for row in range(size):
    for col in range(size):
        i = row * (size + 1) + col
        faces.append((i, i + 1, i + size + 2, i + size + 1))
mesh = bpy.data.meshes.new('Curved paper mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
paper = bpy.data.objects.new('Post-it — editable paper model', mesh)
scene.collection.objects.link(paper)
for face in mesh.polygons:
    face.use_smooth = True
solid = paper.modifiers.new('Paper thickness', 'SOLIDIFY')
solid.thickness = 0.001

mat = bpy.data.materials.new('Matte paper with fine grain')
mat.use_nodes = True
nodes, links = mat.node_tree.nodes, mat.node_tree.links
bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
bsdf.inputs['Roughness'].default_value = 0.9
noise = nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 450
noise.inputs['Detail'].default_value = 2
bump = nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = 0.10
bump.inputs['Distance'].default_value = 0.0004
links.new(noise.outputs['Fac'], bump.inputs['Height'])
links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
mesh.materials.append(mat)

# Raised adhesive band produces a subtle seam at the top.
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0.445, 0.006))
band = bpy.context.object
band.name = 'Adhesive band'
band.scale = (1, 0.11, 1)
band.data.materials.append(mat)

light_data = bpy.data.lights.new('Large upper-left softbox', 'AREA')
light_data.energy = 35
light_data.size = 2.5
light = bpy.data.objects.new('Softbox', light_data)
scene.collection.objects.link(light)
light.location = (-1.2, 1.5, 2.5)
light.rotation_euler = (Vector((0, 0, 0)) - light.location).to_track_quat('-Z', 'Y').to_euler()
camera_data = bpy.data.cameras.new('Orthographic UI camera')
camera = bpy.data.objects.new('Camera', camera_data)
scene.collection.objects.link(camera)
camera.location = (0, 0, 3)
camera.rotation_euler = (0, 0, 0)
camera_data.type = 'ORTHO'
camera_data.ortho_scale = 1.035
scene.camera = camera

# Include the AI-generated visual reference in the .blend, with rendering disabled.
reference = bpy.data.images.load(str(root / 'Art/post-it-generated.png'))
reference.pack()
ref = bpy.data.objects.new('Generated post-it reference', None)
ref.empty_display_type = 'IMAGE'
ref.data = reference
ref.location = (1.4, 0, 0)
ref.hide_render = True
scene.collection.objects.link(ref)

colors = {
    'yellow': (0.96, 0.82, 0.41, 1),
    'peach': (0.96, 0.66, 0.49, 1),
    'mint': (0.64, 0.81, 0.57, 1),
    'blue': (0.59, 0.76, 0.92, 1),
    'lilac': (0.76, 0.63, 0.94, 1),
}
requested = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else set()
for name, color in colors.items():
    if requested and name not in requested:
        continue
    bsdf.inputs['Base Color'].default_value = color
    scene.render.filepath = str(output / f'paper-{name}.png')
    bpy.ops.render.render(write_still=True)
bsdf.inputs['Base Color'].default_value = colors['yellow']
bpy.ops.wm.save_as_mainfile(filepath=str(root / 'Art/Blender/post-it.blend'))
print('Saved model and requested transparent paper renders.')
