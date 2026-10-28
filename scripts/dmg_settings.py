import os

app = defines["app"]
background = defines["background"]

files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {os.path.basename(app): (170, 190), "Applications": (470, 190)}
background = background
window_rect = ((200, 160), (640, 400))
icon_size = 112
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
format = "UDZO"
