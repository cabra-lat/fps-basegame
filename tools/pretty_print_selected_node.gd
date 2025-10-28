@tool
extends EditorScript

func _run():
    # Get the current editor selection
  var selection = get_editor_interface().get_selection()
  var selected_nodes: Array[Node] = selection.get_selected_nodes()

  if selected_nodes.is_empty():
    push_warning("No nodes selected!")
    return

  print("=== PRETTY PRINT SELECTED NODES ===")

  for node in selected_nodes:
    node.print_tree_pretty()
