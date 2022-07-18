from xml.dom import minidom

# parse an xml file by name
file = minidom.parse('ecad-export.xml')

# use getElementsByTagName() to get tag
objects = file.getElementsByTagName('o')

# all item attributes
print('Object attribute:')
for elem in objects:
    node_name = elem.attributes['name'].value
    node_type = elem.attributes['type'].value
    node_id = elem.attributes['id'].value
    print(f"[name]: {node_name} [type]: {node_type} [id]: {node_id}")

# one specific item's data
# print('\nmodel #2 data:')
# print(objects[1].firstChild.data)
# print(objects[1].childNodes[0].data)
#
# # all items data
# print('\nAll model data:')
# for elem in objects:
#     print(elem.firstChild.data)
