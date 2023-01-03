    li t1, 0x3ff00
    li t2, 0xf5555
    li t3, 0x7ffff
    li t4, 0x2f2f2
    li t5, 0x1234

    li x1, 0x1000
    li x2, 0x1011
    li x3, 0x1100
    li x4, 0x1020

    sw t1, 0(x1)
    sw t2, 0(x1)
    lw  x5, 0(x1)
    sw t3, 0(x1)
    lw  x6, 0(x1)
    lw  x7, 0(x1)
    sw t4, 0(x1)

    sw t5, 0(x2)
    lw x8, 0(x2)
    sw t1, 0(x2)
    lw x9, 0(x2)
    sw t2, 0(x2)
    lw x10, 0(x2)
    sw t3, 0(x2)

    sw t3, 0(x3)
    lw x5, 0(x3)
    lw x6, 0(x3)
    lw x7, 0(x3)
    lw x8, 0(x3)
    lw x9, 0(x3)
    lw x10, 0(x3)

    sw t1, 0(x4)
    sw t2, 0(x4)
    sw x1, 0(x4)
    sw t3, 0(x4)
    sw t4, 0(x4)
    sw x2, 0(x4)
    sw t5, 0(x4)

    sw t2, 0(x2)
    lw  x5, 0(x2)
    lw  x6, 0(x2)
    sw t3, 0(x2)
    lw  x6, 0(x2)
    sw t4, 0(x2)
    lw  x7, 0(x2)
    lw  x8, 0(x2)
    sw t5, 0(x2)
    lw  x9, 0(x2)
    sw t1, 0(x2)
    lw  x10, 0(x2)

    wfi