# ML Kit text recognition (receipt scanning) only bundles the Latin model. The plugin also refers to the
# Chinese, Devanagari, Japanese and Korean recognisers, which are not included, so R8 must not stop on them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
