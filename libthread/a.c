#include <u.h>
#include <libc.h>

void f(char *c, int i1, int i2, int i3, int i4, int i5, int i6)
{
print(c, i1, i2, i3, i4, i5, i6);
}

int
main(){
f("x", 1, 2, 3, 4, 5, 6);
return 1;
}
