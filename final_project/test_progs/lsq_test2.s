li t1, 0x3ff00
li t2, 0xf5555
li t3, 0x7ffff
li t4, 0x2f2f2

li x1, 0x1000
li x2, 0x1100
li x3, 0x0100

sw t1, 0(x1)
lw x9, 0(x1)
lh x5, 0(x1)
lb x6, 0(x1)

sh t2, 0(x2)
lw x7, 0(x2)
sb x7, 0(x2)
lh x8, 0(x2)

sw t3, 0(x3)
sb t4, 0(x3)
lw x10, 0(x3)
lh x11, 0(x3)

wfi
