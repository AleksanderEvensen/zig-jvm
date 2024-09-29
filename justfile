compile-java:
    javac -d java-out ./java/Main.java

java-parse:
    javap -v -cp java-out Main