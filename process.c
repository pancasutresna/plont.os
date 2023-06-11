#include "process.h"
#include "trap.h"
#include "memory.h"
#include "print.h"
#include "lib.h"
#include "debug.h"

extern struct TSS Tss;
static struct Process process_table[NUM_PROC];
static int pid_num = 1;
void main(void);

static void set_tss(struct Process *proc)
{
    Tss.rsp0 = proc->stack + STACK_SIZE;
}

static struct Process* find_unused_process(void) 
{
    struct Process *process = NULL;

    for (int i = 0; i< NUM_PROC; i++){
        if (process_table[i].state == PROC_UNUSED) {
            process = &process_table[i];
            break;
        }
    }

    return process;
}

static void set_process_entry(struct Process *proc)
{
    uint64_t stack_top;
    proc->state = PROC_INIT;
    proc->pid = pid_num++;

    proc->stack = (uint64_t)kalloc();
    ASSERT(proc->stack != 0);

    memset((void*)proc->stack, 0, PAGE_SIZE); // clear stack
    stack_top = proc->stack + STACK_SIZE;

    proc->tf = (struct TrapFrame*)(stack_top - sizeof(struct TrapFrame));
    proc->tf->cs = 0x10|3; // user mode code segment 
    proc->tf->rip = 0x400000; // entry point of the process (0x400000) 
    proc->tf->ss = 0x18|3; // user mode data segment 
    proc->tf->rsp = 0x400000 + PAGE_SIZE; // top of the user stack (0x400000 + 4KB)
    proc->tf->rflags = 0x202; // IF = 1, IOPL = 0x2 

    proc->page_map = setup_kvm(); // setup kernel page table for process
    ASSERT(proc->page_map != 0);
    ASSERT(setup_uvm(proc->page_map, (uint64_t)main, PAGE_SIZE));
}

void init_process(void)
{
    struct Process *proc = find_unused_process(); // find unused process entry
    ASSERT(proc == &process_table[0]); // process 0 is the only unused process entry

    set_process_entry(proc);
}

void launch(void)
{
    set_tss(&process_table[0]); // set TSS for process 0
    switch_vm(process_table[0].page_map); // switch to process 0's page table
    pstart(process_table[0].tf); // start process 0 with its trap frame
}

void main(void)
{
    char *p = (char*)0xffff800000200020; // 0x200020 is the address of the first page of the process
    *p = 1; // page fault here because the page is not mapped yet
}

