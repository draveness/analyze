provider objc_runtime
{
    probe objc_exception_throw(void *id);
    probe objc_exception_rethrow();
};
