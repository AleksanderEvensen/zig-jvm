# Java Virtual Machine written in Zig
Just like my other project [the Rust JVM](https://github.com/AleksanderEvensen/Rusty-JVM), I'm making a JVM in Zig to learn the language.

I will also utilize this opportunity to improve on my old design.
I'll admit that the Rust version wasn't very "Rusty" and could've been solved in a much better way.

Current Output of the program:
```
Magic: 0xCAFEBABE
Version: 66.0
This Class: #14 'Main'
Super Class: #4 'java/lang/Object'
Constant pool(20):
  #1: MethodRef: #2.#3 'java/lang/Object.<init>:()V'
  #2: Class: #4 'java/lang/Object'
  #3: NameAndType: #5.#6 '<init>:()V'
  #4: Utf8: 'java/lang/Object'
  #5: Utf8: '<init>'
  #6: Utf8: '()V'
  #7: MethodRef: #8.#9 'java/lang/System.exit:(I)V'
  #8: Class: #10 'java/lang/System'
  #9: NameAndType: #11.#12 'exit:(I)V'
  #10: Utf8: 'java/lang/System'
  #11: Utf8: 'exit'
  #12: Utf8: '(I)V'
  #13: Class: #14 'Main'
  #14: Utf8: 'Main'
  #15: Utf8: 'Code'
  #16: Utf8: 'LineNumberTable'
  #17: Utf8: 'main'
  #18: Utf8: '([Ljava/lang/String;)V'
  #19: Utf8: 'SourceFile'
  #20: Utf8: 'Main.java'
Methods(2):
  #1: <init>:()V
    Code
      Max Stack: 1
      Max Locals: 1
      Code Length: 5
      Instructions:
        { 42, 183, 0, 1, 177 }
  #2: main:([Ljava/lang/String;)V
    Code
      Max Stack: 2
      Max Locals: 4
      Code Length: 13
      Instructions:
        { 3, 60, 3, 61, 27, 28, 96, 62, 29, 184, 0, 7, 177 }
```


## Reading material
[The Java Virtual Machine Specification](https://docs.oracle.com/javase/specs/jvms/se23/html/index.html);
 - [Chapter 4: The `class` File Format](https://docs.oracle.com/javase/specs/jvms/se23/html/jvms-4.html)
 - [Chapter 6: The JVM Instruction Set](https://docs.oracle.com/javase/specs/jvms/se23/html/jvms-6.html)