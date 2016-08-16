#ifndef	_exc_server_
#define	_exc_server_

/* Module exc */

#include <string.h>
#include <mach/ndr.h>
#include <mach/boolean.h>
#include <mach/kern_return.h>
#include <mach/notify.h>
#include <mach/mach_types.h>
#include <mach/message.h>
#include <mach/mig_errors.h>
#include <mach/port.h>

#ifdef AUTOTEST
#ifndef FUNCTION_PTR_T
#define FUNCTION_PTR_T
typedef void (*function_ptr_t)(mach_port_t, char *, mach_msg_type_number_t);
typedef struct {
        char            *name;
        function_ptr_t  function;
} function_table_entry;
typedef function_table_entry   *function_table_t;
#endif /* FUNCTION_PTR_T */
#endif /* AUTOTEST */

#ifndef	exc_MSG_COUNT
#define	exc_MSG_COUNT	3
#endif	/* exc_MSG_COUNT */

#include <mach/std_types.h>
#include <mach/mig.h>
#include <mach/mig.h>
#include <mach/mach_types.h>

#ifdef __BeforeMigServerHeader
__BeforeMigServerHeader
#endif /* __BeforeMigServerHeader */


/* Routine exception_raise */
#ifdef	mig_external
mig_external
#else
extern
#endif	/* mig_external */
kern_return_t catch_exception_raise
(
	mach_port_t exception_port,
	mach_port_t thread,
	mach_port_t task,
	exception_type_t exception,
	exception_data_t code,
	mach_msg_type_number_t codeCnt
);

/* Routine exception_raise_state */
#ifdef	mig_external
mig_external
#else
extern
#endif	/* mig_external */
kern_return_t catch_exception_raise_state
(
	mach_port_t exception_port,
	exception_type_t exception,
	const exception_data_t code,
	mach_msg_type_number_t codeCnt,
	int *flavor,
	const thread_state_t old_state,
	mach_msg_type_number_t old_stateCnt,
	thread_state_t new_state,
	mach_msg_type_number_t *new_stateCnt
);

/* Routine exception_raise_state_identity */
#ifdef	mig_external
mig_external
#else
extern
#endif	/* mig_external */
kern_return_t catch_exception_raise_state_identity
(
	mach_port_t exception_port,
	mach_port_t thread,
	mach_port_t task,
	exception_type_t exception,
	exception_data_t code,
	mach_msg_type_number_t codeCnt,
	int *flavor,
	thread_state_t old_state,
	mach_msg_type_number_t old_stateCnt,
	thread_state_t new_state,
	mach_msg_type_number_t *new_stateCnt
);

extern boolean_t exc_server(
		mach_msg_header_t *InHeadP,
		mach_msg_header_t *OutHeadP);

extern mig_routine_t exc_server_routine(
		mach_msg_header_t *InHeadP);


/* Description of this subsystem, for use in direct RPC */
extern const struct catch_exc_subsystem {
	mig_server_routine_t	server;	/* Server routine */
	mach_msg_id_t	start;	/* Min routine number */
	mach_msg_id_t	end;	/* Max routine number + 1 */
	unsigned int	maxsize;	/* Max msg size */
	vm_address_t	reserved;	/* Reserved */
	struct routine_descriptor	/*Array of routine descriptors */
		routine[3];
} catch_exc_subsystem;

/* typedefs for all requests */

#ifndef __Request__exc_subsystem__defined
#define __Request__exc_subsystem__defined

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		/* start of the kernel processed data */
		mach_msg_body_t msgh_body;
		mach_msg_port_descriptor_t thread;
		mach_msg_port_descriptor_t task;
		/* end of the kernel processed data */
		NDR_record_t NDR;
		exception_type_t exception;
		mach_msg_type_number_t codeCnt;
		integer_t code[2];
	} __Request__exception_raise_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		exception_type_t exception;
		mach_msg_type_number_t codeCnt;
		integer_t code[2];
		int flavor;
		mach_msg_type_number_t old_stateCnt;
		natural_t old_state[144];
	} __Request__exception_raise_state_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		/* start of the kernel processed data */
		mach_msg_body_t msgh_body;
		mach_msg_port_descriptor_t thread;
		mach_msg_port_descriptor_t task;
		/* end of the kernel processed data */
		NDR_record_t NDR;
		exception_type_t exception;
		mach_msg_type_number_t codeCnt;
		integer_t code[2];
		int flavor;
		mach_msg_type_number_t old_stateCnt;
		natural_t old_state[144];
	} __Request__exception_raise_state_identity_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif
#endif /* !__Request__exc_subsystem__defined */


/* union of all requests */

#ifndef __RequestUnion__catch_exc_subsystem__defined
#define __RequestUnion__catch_exc_subsystem__defined
union __RequestUnion__catch_exc_subsystem {
	__Request__exception_raise_t Request_exception_raise;
	__Request__exception_raise_state_t Request_exception_raise_state;
	__Request__exception_raise_state_identity_t Request_exception_raise_state_identity;
};
#endif /* __RequestUnion__catch_exc_subsystem__defined */
/* typedefs for all replies */

#ifndef __Reply__exc_subsystem__defined
#define __Reply__exc_subsystem__defined

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		kern_return_t RetCode;
	} __Reply__exception_raise_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		kern_return_t RetCode;
		int flavor;
		mach_msg_type_number_t new_stateCnt;
		natural_t new_state[144];
	} __Reply__exception_raise_state_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		kern_return_t RetCode;
		int flavor;
		mach_msg_type_number_t new_stateCnt;
		natural_t new_state[144];
	} __Reply__exception_raise_state_identity_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif
#endif /* !__Reply__exc_subsystem__defined */


/* union of all replies */

#ifndef __ReplyUnion__catch_exc_subsystem__defined
#define __ReplyUnion__catch_exc_subsystem__defined
union __ReplyUnion__catch_exc_subsystem {
	__Reply__exception_raise_t Reply_exception_raise;
	__Reply__exception_raise_state_t Reply_exception_raise_state;
	__Reply__exception_raise_state_identity_t Reply_exception_raise_state_identity;
};
#endif /* __RequestUnion__catch_exc_subsystem__defined */

#ifndef subsystem_to_name_map_exc
#define subsystem_to_name_map_exc \
    { "exception_raise", 2401 },\
    { "exception_raise_state", 2402 },\
    { "exception_raise_state_identity", 2403 }
#endif

#ifdef __AfterMigServerHeader
__AfterMigServerHeader
#endif /* __AfterMigServerHeader */

#endif	 /* _exc_server_ */
