li t1, 0x3ff00
li t2, 0xf5555
li t3, 0x7ffff
li t4, 0x2f2f2
li t5, 0x12345

li x1, 0x100
li x2, 0xff
li x3, 0x2e
li x4, 0x110

sw t1, 0(x1)
sh t2, 0(x1)
lb x5, 0(x1)
sw t3, 0(x1)
lh x6, 0(x1)
lw x7, 0(x1)
sb t4, 0(x1)

sb t5, 0(x2)
lw x8, 0(x2)
sw t1, 0(x2)
lh x9, 0(x2)
sh t2, 0(x2)
lb x10,0(x2)
sw t3, 0(x2)

sh t3, 0(x3)
lh x5, 0(x3)
lb x6, 0(x3)
lw x7, 0(x3)
lb x8, 0(x3)
lw x9, 0(x3)
lh x10, 0(x3)

sw t1, 0(x4)
sh t2, 0(x4)
sb x1, 0(x4)
sb t3, 0(x4)
sh t4, 0(x4)
sw x2, 0(x4)
sb t5, 0(x4)

sw t2, 0(x2)
lh x5, 0(x2)
lb x6, 0(x2)
sb t3, 0(x2)
lw x6, 0(x2)
sw t4, 0(x2)
lw x7, 0(x2)
lb x8, 0(x2)
sh t5, 0(x2)
lw x9, 0(x2)
sw t1, 0(x2)
lh x10,0(x2)

sb t1, 0(x1)
sw t2, 0(x1)
sh t3, 0(x1)
sw t4, 0(x1)
sw t5, 0(x1)
lw x11, 0(x1)
lb x12, 0(x1)
sh x12, 0(x1)