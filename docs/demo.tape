# vhs source for docs/demo.gif
#
# How to record:
#   1. Install vhs:  https://github.com/charmbracelet/vhs
#   2. Make sure GlassFish is running and your Maven project is deployed
#      via `./gf run` from a real Jakarta EE project directory.
#   3. From the project root, run:  vhs docs/demo.tape
#   4. Commit the produced docs/demo.gif.
#
# Tweak the Set commands below to match your terminal aesthetic.

Output docs/demo.gif

Set FontSize 14
Set Width 1100
Set Height 600
Set Theme "Dracula"
Set PlaybackSpeed 1.0
Set Padding 20

# Open with the project root visible.
Type "# Make a change to a Java file..."
Enter
Sleep 600ms

# Replace this with a real edit against your demo project.
# Example: change a return value in a controller class.
Type "sed -i 's/Hello/Hello, world/' src/main/java/com/example/HelloController.java"
Enter
Sleep 800ms

Type "# ...then hot-swap it into the running GlassFish."
Enter
Sleep 500ms

Type "./gf sync -v"
Enter

# Wait for the hot-swap output (~3-6s).
Sleep 6s

Type "# Done. No restart, no redeploy."
Enter
Sleep 2s
