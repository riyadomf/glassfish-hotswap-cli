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

# Brief beat so the opening prompt is visible.
Sleep 800ms

# Step 1: Edit a Java source file. The `#` prefix marks narration, not commands.
Type "# Step 1: Make a small change to a Java file..."
Enter
Sleep 800ms

Type "sed -i 's/logger.info/logger.error/' src/main/java/com/dsi/bcic/shared/user/view/UserView.java"
Sleep 600ms
Enter
Sleep 800ms

# Step 2: Hot-swap the change into the running GlassFish.
Type "# Step 2: Hot-swap it into the running GlassFish..."
Enter
Sleep 800ms

Type "./gf sync -v"
Sleep 400ms
Enter

# Wait for the hot-swap output (~3-8s).
Sleep 8s

# Wrap up.
Type "# Done. No restart, no redeploy."
Enter

# Hold the final frame so viewers can read the result.
Sleep 2500ms
