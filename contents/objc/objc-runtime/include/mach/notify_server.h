#ifndef	_notify_server_
#define	_notify_server_

/* Module notify */

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

#ifndef	notify_MSG_COUNT
#define	notify_MSG_COUNT	9
#endif	/* notify_MSG_COUNT */

#include <mach/std_types.h>
#include <mach/mig.h>

#ifdef __BeforeMigServerHeader
__BeforeMigServerHeader
#endif /* __BeforeMigServerHeader */


/* SimpleRoutine mach_notify_port_deleted */
#ifdef	mig_external
mig_external
#else
extern
#endif	/* mig_external */
kern_return_t do_mach_notify_port_deleted
(
	mach_port_t notify,
	mach_port_name_t name
);

/* SimpleRoutine mach_notify_port_destroyed */
#ifdef	mig_external
mig_external
#else
extern
#endif	/* mig_external */
kern_return_t do_mach_notify_port_destroyed
(
	mach_port_t notify,
	mach_port_t rights
);

/* SimpleRoutine mach_notify_no_senders */
#ifdef	mig_external
mig_external
#else
extern
#endif	/* mig_external */
kern_return_t do_mach_notify_no_senders
(
	mach_port_t notify,
	mach_port_mscount_t mscount
);

/* SimpleRoutine mach_notify_send_once */
#ifdef	mig_external
mig_external
#else
extern
#endif	/* mig_external */
kern_return_t do_mach_notify_send_once
(
	mach_port_t notify
);

/* SimpleRoutine mach_notify_dead_name */
#ifdef	mig_external
mig_external
#else
extern
#endif	/* mig_external */
kern_return_t do_mach_notify_dead_name
(
	mach_port_t notify,
	mach_port_name_t name
);

extern boolean_t notify_server(
		mach_msg_header_t *InHeadP,
		mach_msg_header_t *OutHeadP);

extern mig_routine_t notify_server_routine(
		mach_msg_header_t *InHeadP);


/* Description of this subsystem, for use in direct RPC */
extern const struct do_notify_subsystem {
	mig_server_routine_t	server;	/* Server routine */
	mach_msg_id_t	start;	/* Min routine number */
	mach_msg_id_t	end;	/* Max routine number + 1 */
	unsigned int	maxsize;	/* Max msg size */
	vm_address_t	reserved;	/* Reserved */
	struct routine_descriptor	/*Array of routine descriptors */
		routine[9];
} do_notify_subsystem;

/* typedefs for all requests */

#ifndef __Request__notify_subsystem__defined
#define __Request__notify_subsystem__defined

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		mach_port_name_t name;
	} __Request__mach_notify_port_deleted_t;
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
		mach_msg_port_descriptor_t rights;
		/* end of the kernel processed data */
	} __Request__mach_notify_port_destroyed_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		mach_port_mscount_t mscount;
	} __Request__mach_notify_no_senders_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
	} __Request__mach_notify_send_once_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		mach_port_name_t name;
	} __Request__mach_notify_dead_name_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif
#endif /* !__Request__notify_subsystem__defined */


/* union of all requests */

#ifndef __RequestUnion__do_notify_subsystem__defined
#define __RequestUnion__do_notify_subsystem__defined
union __RequestUnion__do_notify_subsystem {
	__Request__mach_notify_port_deleted_t Request_mach_notify_port_deleted;
	__Request__mach_notify_port_destroyed_t Request_mach_notify_port_destroyed;
	__Request__mach_notify_no_senders_t Request_mach_notify_no_senders;
	__Request__mach_notify_send_once_t Request_mach_notify_send_once;
	__Request__mach_notify_dead_name_t Request_mach_notify_dead_name;
};
#endif /* __RequestUnion__do_notify_subsystem__defined */
/* typedefs for all replies */

#ifndef __Reply__notify_subsystem__defined
#define __Reply__notify_subsystem__defined

#ifdef  __MigPackStructs
#pragma pack(4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		kern_return_t RetCode;
	} __Reply__mach_notify_port_deleted_t;
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
	} __Reply__mach_notify_port_destroyed_t;
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
	} __Reply__mach_notify_no_senders_t;
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
	} __Reply__mach_notify_send_once_t;
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
	} __Reply__mach_notify_dead_name_t;
#ifdef  __MigPackStructs
#pragma pack()
#endif
#endif /* !__Reply__notify_subsystem__defined */


/* union of all replies */

#ifndef __ReplyUnion__do_notify_subsystem__defined
#define __ReplyUnion__do_notify_subsystem__defined
union __ReplyUnion__do_notify_subsystem {
	__Reply__mach_notify_port_deleted_t Reply_mach_notify_port_deleted;
	__Reply__mach_notify_port_destroyed_t Reply_mach_notify_port_destroyed;
	__Reply__mach_notify_no_senders_t Reply_mach_notify_no_senders;
	__Reply__mach_notify_send_once_t Reply_mach_notify_send_once;
	__Reply__mach_notify_dead_name_t Reply_mach_notify_dead_name;
};
#endif /* __RequestUnion__do_notify_subsystem__defined */

#ifndef subsystem_to_name_map_notify
#define subsystem_to_name_map_notify \
    { "mach_notify_port_deleted", 65 },\
    { "mach_notify_port_destroyed", 69 },\
    { "mach_notify_no_senders", 70 },\
    { "mach_notify_send_once", 71 },\
    { "mach_notify_dead_name", 72 }
#endif

#ifdef __AfterMigServerHeader
__AfterMigServerHeader
#endif /* __AfterMigServerHeader */

#endif	 /* _notify_server_ */
