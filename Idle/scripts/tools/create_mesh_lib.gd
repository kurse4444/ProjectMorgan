@tool
extends EditorScript

func _run():
    var folder_path = "res://art/Kenney Nature Kit/"
    var dir = DirAccess.open(folder_path)
    
    # Create root node
    var root = Node3D.new()
    root.name = "KenneyNatureKitLibrary"
    
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        
        while file_name != "":
            if file_name.ends_with(".obj"):
                var mesh_path = folder_path + file_name
                var mesh = load(mesh_path)
                
                if mesh:
                    var item_name = file_name.get_basename()
                    
                    # Create mesh instance as root of each item
                    var mesh_instance = MeshInstance3D.new()
                    mesh_instance.mesh = mesh
                    mesh_instance.name = item_name
                    
                    # Add static body as child with same name
                    var static_body = StaticBody3D.new()
                    static_body.name = item_name + "_StaticBody"
                    
                    # Add collision shape to static body with same name
                    var collision_shape = CollisionShape3D.new()
                    collision_shape.name = item_name + "_Collision"
                    collision_shape.shape = mesh.create_trimesh_shape()
                    
                    # Build hierarchy first
                    root.add_child(mesh_instance)
                    mesh_instance.add_child(static_body)
                    static_body.add_child(collision_shape)
                    
                    # Set owners after hierarchy is built
                    mesh_instance.owner = root
                    static_body.owner = root
                    collision_shape.owner = root
                    
                    print("Added: ", file_name)
            
            file_name = dir.get_next()
        
        dir.list_dir_end()
        
        # Save scene
        var scene = PackedScene.new()
        scene.pack(root)
        var scene_path = "res://kenney_nature_kit_library.tscn"
        var err = ResourceSaver.save(scene, scene_path)
        
        if err == OK:
            print("Scene saved to: ", scene_path)
            print("Edit collision shapes, then Scene > Convert To > MeshLibrary")
        else:
            print("Error saving scene: ", err)
    else:
        print("Could not open directory: ", folder_path)