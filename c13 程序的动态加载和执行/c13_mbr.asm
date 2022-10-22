         ;代码清单13-1
         ;文件名：c13_mbr.asm
         ;文件说明：硬盘主引导扇区代码 
         ;创建日期：2011-10-28 22:35        ;设置堆栈段和栈指针 
         
         core_base_address equ 0x00040000   ;常数，内核加载的起始内存地址 
         core_start_sector equ 0x00000001   ;常数，内核的起始逻辑扇区号 
         
; 此处可以添加段定义
; 当然，因为本程序只有一个段，不加也会默认定义好
; 但是如果我们加上了vstart，下面的计算就不用加上0x7c00了
; SECTION mbr align=16 vstart=0x7c00
;-------------------------------------------------------------------------------

         mov ax,cs      
         mov ss,ax
         mov sp,0x7c00
      
         ;计算GDT所在的逻辑段地址
         mov eax,[cs:pgdt+0x7c00+0x02]      ;GDT的32位物理地址 
         xor edx,edx
         mov ebx,16
         div ebx                            ;分解成16位逻辑地址 

         mov ds,eax                         ;令DS指向该段以进行操作
         mov ebx,edx                        ;段内起始偏移地址 

         ;跳过0#号描述符的槽位 
         ;创建1#描述符，这是一个数据段，对应0~4GB的线性地址空间
         mov dword [ebx+0x08],0x0000ffff    ;基地址为0，段界限为0xFFFFF
         mov dword [ebx+0x0c],0x00cf9200    ;粒度为4KB，存储器段描述符 

         ;创建保护模式下初始代码段描述符
         mov dword [ebx+0x10],0x7c0001ff    ;基地址为0x00007c00，界限0x1FF 
         mov dword [ebx+0x14],0x00409800    ;粒度为1个字节，代码段描述符 

         ;建立保护模式下的堆栈段描述符      ;基地址为0x00007C00，界限0xFFFFE 
         mov dword [ebx+0x18],0x7c00fffe    ;粒度为4KB 
         mov dword [ebx+0x1c],0x00cf9600
         
         ;建立保护模式下的显示缓冲区描述符   
         mov dword [ebx+0x20],0x80007fff    ;基地址为0x000B8000，界限0x07FFF 
         mov dword [ebx+0x24],0x0040920b    ;粒度为字节
         
         ;初始化描述符表寄存器GDTR
         mov word [cs: pgdt+0x7c00],39      ;描述符表的界限   
 
         lgdt [cs: pgdt+0x7c00]
      
         in al,0x92                         ;南桥芯片内的端口 
         or al,0000_0010B
         out 0x92,al                        ;打开A20

         cli                                ;中断机制尚未工作

         mov eax,cr0
         or eax,1
         mov cr0,eax                        ;设置PE位
      
         ;以下进入保护模式... ...
         jmp dword 0x0010:flush             ;16位的描述符选择子：32位偏移
                                            ;清流水线并串行化处理器
         [bits 32]               
  flush:                                  
         mov eax,0x0008                     ;加载数据段(0..4GB)选择子
         mov ds,eax
      
         mov eax,0x0018                     ;加载堆栈段选择子 
         mov ss,eax
         xor esp,esp                        ;堆栈指针 <- 0 
         
         ;以下加载系统核心程序 
         mov edi,core_base_address 
      
         mov eax,core_start_sector
         mov ebx,edi                        ;起始地址 
         call read_hard_disk_0              ;以下读取程序的起始部分（一个扇区） 
      
         ;以下判断整个程序有多大
         mov eax,[edi]                      ;核心程序尺寸core_length
         xor edx,edx 
         mov ecx,512                        ;512字节每扇区
         div ecx            ;将EDX:EAX除以512，得到的商EAX是扇区数，余edx 

         or edx,edx
         jnz @1                             ;未除尽，因此结果比实际扇区数少1 
         dec eax                            ;已经读了一个扇区，扇区总数减1 
   @1:
         or eax,eax                         ;考虑实际长度≤512个字节的情况 
         jz setup                           ;EAX=0 ?

         ;读取剩余的扇区
         mov ecx,eax                        ;32位模式下的LOOP使用ECX
         mov eax,core_start_sector
         inc eax                            ;从下一个逻辑扇区接着读
   @2:
         call read_hard_disk_0
         inc eax
         loop @2                            ;循环读，直到读完整个内核 

 setup:
         mov esi,[0x7c00+pgdt+0x02]         ;不可以在代码段内寻址pgdt，但可以
                                            ;通过4GB的段来访问
         ;建立公用例程段描述符
         mov eax,[edi+0x04]                 ;公用例程代码段起始汇编地址
         mov ebx,[edi+0x08]                 ;核心数据段汇编地址
         sub ebx,eax
         dec ebx                            ;公用例程段界限 
         add eax,edi                        ;公用例程段基地址
         mov ecx,0x00409800                 ;字节粒度的代码段描述符
         call make_gdt_descriptor
         mov [esi+0x28],eax
         mov [esi+0x2c],edx
       
         ;建立核心数据段描述符
         mov eax,[edi+0x08]                 ;核心数据段起始汇编地址
         mov ebx,[edi+0x0c]                 ;核心代码段汇编地址 
         sub ebx,eax
         dec ebx                            ;核心数据段界限
         add eax,edi                        ;核心数据段基地址
         mov ecx,0x00409200                 ;字节粒度的数据段描述符 
         call make_gdt_descriptor
         mov [esi+0x30],eax
         mov [esi+0x34],edx 
      
         ;建立核心代码段描述符
         mov eax,[edi+0x0c]                 ;核心代码段起始汇编地址
         mov ebx,[edi+0x00]                 ;程序总长度
         sub ebx,eax
         dec ebx                            ;核心代码段界限
         add eax,edi                        ;核心代码段基地址
         mov ecx,0x00409800                 ;字节粒度的代码段描述符
         call make_gdt_descriptor
         mov [esi+0x38],eax
         mov [esi+0x3c],edx

         mov word [0x7c00+pgdt],63          ;描述符表的界限
                                        
         lgdt [0x7c00+pgdt]                  

         jmp far [edi+0x10]  
       
;-------------------------------------------------------------------------------
read_hard_disk_0:                        ;从硬盘读取一个逻辑扇区
                                         ;EAX=逻辑扇区号
                                         ;DS:EBX=目标缓冲区地址
                                         ;返回：EBX=EBX+512 
         push eax 
         push ecx
         push edx
      
         push eax
         
         ; 本书中用的都是独立编址的端口，访问端口只能用in和out这种特殊指令
         ; Intel系统只允许65526(0x10000)个端口存在,所以端口号长两字节
         ; in al,dx 或 in ax,dx 只允许这两个寄存器，dx保存端口号，al或ax是目的
         ; in al,0xf0 ;源也可以是立即数,这句的意思是读0xf0号端口
         ; out 反过来即可

         ; 本书中采用LBA28来访问硬盘，LABA28是一种逻辑扇区编址方法，将扇区从0到0xfffffff编号，共可表达2^28个扇区，每个扇区512字节，共可管理128GB
         mov dx,0x1f2
         mov al,1                        ;读取的扇区数，如果为0代表读256个
         out dx,al                       ;设置读取的扇区数
        
         ;设置要读的LBA（逻辑块地址）,因为28位太长，故分成4次，依次写入0x1f3~0x1f6端口
         inc dx                          ;0x1f3
         pop eax
         out dx,al                       ;LBA地址7~0

         inc dx                          ;0x1f4
         mov cl,8
         shr eax,cl
         out dx,al                       ;LBA地址15~8

         inc dx                          ;0x1f5
         shr eax,cl
         out dx,al                       ;LBA地址23~16

         inc dx                          ;0x1f6端口，低位是LBA地址，高位可表示是第几硬盘
         shr eax,cl
         or al,0xe0                      ;第一硬盘  LBA地址27~24
         out dx,al

         inc dx                          ;0x1f7端口，可发送读写命令，也可读取硬盘状态
         mov al,0x20                     ;读命令
         out dx,al

  .waits:
         in al,dx
         and al,0x88
         cmp al,0x08
         jnz .waits                      ;不忙，且硬盘已准备好数据传输 

         mov ecx,256                     ;总共要读取的字数
         mov dx,0x1f0
  .readw:
         in ax,dx                        ;读两字节
         mov [ebx],ax
         add ebx,2
         loop .readw

         pop edx
         pop ecx
         pop eax
      
         ret

;-------------------------------------------------------------------------------
make_gdt_descriptor:                     ;构造描述符
                                         ;输入：EAX=线性基地址
                                         ;      EBX=段界限
                                         ;      ECX=属性（各属性位都在原始
                                         ;      位置，其它没用到的位置0） 
                                         ;返回：EDX:EAX=完整的描述符
         mov edx,eax
         shl eax,16                     
         or ax,bx                        ;描述符前32位(EAX)构造完毕
      
         and edx,0xffff0000              ;清除基地址中无关的位
         rol edx,8
         bswap edx                       ;装配基址的31~24和23~16  (80486+)
      
         xor bx,bx
         or edx,ebx                      ;装配段界限的高4位
      
         or edx,ecx                      ;装配属性 
      
         ret
      
;-------------------------------------------------------------------------------
         pgdt             dw 0
                          dd 0x00007e00      ;GDT的物理地址
;-------------------------------------------------------------------------------                             
         times 510-($-$$) db 0
                          db 0x55,0xaa