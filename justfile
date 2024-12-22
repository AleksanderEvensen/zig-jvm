compile-java:
    javac -d java-out ./java/Main.java

java-parse:
    javap -v -cp java-out Main

java-runtime:
    javac tools/JRTExtractor.java
    java tools.JRTExtractor -- ./tools/rt.zip

    rm -rf ./java-runtime
    mkdir ./java-runtime
    tar -xf ./tools/rt.zip --include "*java.base**/*" -C ./java-runtime