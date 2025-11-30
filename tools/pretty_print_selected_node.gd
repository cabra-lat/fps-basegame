@tool
extends EditorScript

# Constants for pretty printing
const BRANCH = " ┠╴"
const LEAF = " ┖╴"
const PIPE = " ┃  "
const EMPTY = "    "

# Custom function to print the tree with names and types
func _run():
    var selection = get_editor_interface().get_selection()
    var selected_nodes: Array[Node] = selection.get_selected_nodes()

    if selected_nodes.is_empty():
        push_warning("No nodes selected!")
        return

    print("=== PRETTY PRINT SELECTED NODES WITH TYPES ===")

    for node in selected_nodes:
        # Start the recursive print for each top-level selected node
        _print_node_recursive(node, "", true)

func _print_node_recursive(node: Node, prefix: String, is_last: bool):
    # Determine the current line prefix based on whether this is the last sibling
    var line_prefix = prefix + (LEAF if is_last else BRANCH)

    # Print the node's name and type
    print(line_prefix + node.name + " (" + node.get_class() + ")")

    # Determine the prefix for the children
    # It's either a pipe ("| ") if there are more siblings to come, or empty space
    var child_prefix = prefix + (PIPE if not is_last else EMPTY)

    # Iterate over children, identifying the last child
    var children_count = node.get_child_count()
    for i in range(children_count):
        var child = node.get_child(i)
        var is_last_child = (i == children_count - 1)
        _print_node_recursive(child, child_prefix, is_last_child)
