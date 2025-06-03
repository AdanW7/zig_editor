# zim
This is a sloppy implementation of a vim like terminal editor written in zig.
Currently all chars in a line are stored in an array list, 
and all lines are stored in an array list.

I intend to change this to implement ropes, and then ideally utilize hazard pointers so it can be very efficient in a multithreaded context.
