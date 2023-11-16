// policy.c
#include <unistd.h>

typedef uint16_t compart_id_t;

struct compart {
  /*
   * Name of the compartment
   */
  const char *name;
  /*
   * NULL-terminated array of libraries that belong to the compartment
   */
  const char **libraries;
};

struct policy {
  struct compart *compartments;
  size_t count;
};


/*
 * Other libraries
 * libz.so.6
 * libcares.so.2
 * libaddress_sorting.so.26
 * libre2.so.9
 * libupb.so.26
 * libm.so.5
 * librt.so.1
 * libprotobuf.so.31
 * libexecinfo.so.1
 * libelf.so.2
*/

static struct compart policy_compartments[] = {
  {
    .name = "grpc-libs",
    .libraries = (const char *[]) {
      "libgrpc++_reflection.so.1.48",
      "libgrpc++.so.1.48",
      "libgrpc.so.26",
      "libgpr.so.26",
      NULL
    }
  }, {
    .name = "system-libs",
    .libraries = (const char *[]) {
      "libc++.so.1",
      "libcxxrt.so.1",
      "libgcc_s.so.1",
      "libc.so.7",
      "libthr.so.3",
      NULL
    }
  }, {
    .name = "abseil-libs",
    .libraries = (const char *[]) {
      "libabsl_raw_hash_set.so.2206.0.0",
      "libabsl_hashtablez_sampler.so.2206.0.0",
      "libabsl_hash.so.2206.0.0",
      "libabsl_city.so.2206.0.0",
      "libabsl_low_level_hash.so.2206.0.0",
      "libabsl_statusor.so.2206.0.0",
      "libabsl_bad_variant_access.so.2206.0.0",
      "libabsl_status.so.2206.0.0",
      "libabsl_strerror.so.2206.0.0",
      "libabsl_random_distributions.so.2206.0.0",
      "libabsl_random_seed_sequences.so.2206.0.0",
      "libabsl_random_internal_pool_urbg.so.2206.0.0",
      "libabsl_random_internal_randen.so.2206.0.0",
      "libabsl_random_internal_randen_hwaes.so.2206.0.0",
      "libabsl_random_internal_randen_hwaes_impl.so.2206.0.0",
      "libabsl_random_internal_randen_slow.so.2206.0.0",
      "libabsl_random_internal_platform.so.2206.0.0",
      "libabsl_random_internal_seed_material.so.2206.0.0",
      "libabsl_random_seed_gen_exception.so.2206.0.0",
      "libabsl_cord.so.2206.0.0",
      "libabsl_bad_optional_access.so.2206.0.0",
      "libabsl_cordz_info.so.2206.0.0",
      "libabsl_cord_internal.so.2206.0.0",
      "libabsl_cordz_functions.so.2206.0.0",
      "libabsl_exponential_biased.so.2206.0.0",
      "libabsl_cordz_handle.so.2206.0.0",
      "libabsl_str_format_internal.so.2206.0.0",
      "libabsl_synchronization.so.2206.0.0",
      "libabsl_stacktrace.so.2206.0.0",
      "libabsl_symbolize.so.2206.0.0",
      "libabsl_debugging_internal.so.2206.0.0",
      "libabsl_demangle_internal.so.2206.0.0",
      "libabsl_graphcycles_internal.so.2206.0.0",
      "libabsl_malloc_internal.so.2206.0.0",
      "libabsl_time.so.2206.0.0",
      "libabsl_strings.so.2206.0.0",
      "libabsl_throw_delegate.so.2206.0.0",
      "libabsl_int128.so.2206.0.0",
      "libabsl_strings_internal.so.2206.0.0",
      "libabsl_base.so.2206.0.0",
      "libabsl_spinlock_wait.so.2206.0.0",
      "libabsl_raw_logging_internal.so.2206.0.0",
      "libabsl_log_severity.so.2206.0.0",
      "libabsl_civil_time.so.2206.0.0",
      "libabsl_time_zone.so.2206.0.0",
      "libabsl_flags_parse.so.2206.0.0",
      "libabsl_flags_usage.so.2206.0.0",
      "libabsl_flags_usage_internal.so.2206.0.0",
      "libabsl_flags_usage_marshalling.so.2206.0.0",
      "libabsl_flags_reflection.so.2206.0.0",
      "libabsl_flags_config.so.2206.0.0",
      "libabsl_flags_program_name.so.2206.0.0",
      "libabsl_flags_private_handle_accessor.so.2206.0.0",
      "libabsl_flags_commandlineflag.so.2206.0.0",
      "libabsl_flags_commandlineflag_internal.so.2206.0.0",
      NULL
    }
  }, {
    .name = "crypto-libs",
    .libraries = (const char *[]) {
      "libssl.so.111",
      "libcrypto.so.111",
      NULL
    }
  }
};

struct policy _rtld_compartments = {
  .compartments = policy_compartments,
  .count = sizeof(policy_compartments) / sizeof(*policy_compartments)
};
