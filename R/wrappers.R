#' Calculate the D, f4, f4-ratio, or f3 statistic.
#' @param W,X,Y,Z,A,B,C,O Population names according to the nomenclature used in
#'     Patterson et al., 2012.
#'
#' @inheritParams qpAdm
#'
#' @export
f4ratio <- function(data, X, A, B, C, O, outdir = NULL) {
  check_presence(c(X, A, B, C, O), data)

  # get the path to the population, parameter and log files
  config_prefix <- paste0("qpF4ratio__", as.integer(stats::runif(1, 0, .Machine$integer.max)))
  files <- get_files(outdir, config_prefix)

  create_qpF4ratio_pop_file(X = X, A = A, B = B, C = C, O = O, file = files[["pop_file"]])
  create_par_file(files, data)

  run_cmd("qpF4ratio", par_file = files[["par_file"]], log_file = files[["log_file"]])

  read_output(files[["log_file"]])
}



#' @rdname f4ratio
#'
#' @param f4mode Calculate the f4 statistic instead of the D statistic.
#'
#' @export
d <- function(data, W, X, Y, Z, outdir = NULL, f4mode = FALSE) {
  check_presence(c(W, X, Y, Z), data)

  # get the path to the population, parameter and log files
  config_prefix <- paste0("qpDstat__", as.integer(stats::runif(1, 0, .Machine$integer.max)))
  files <- get_files(outdir, config_prefix)

  create_qpDstat_pop_file(W, X, Y, Z, file = files[["pop_file"]])
  create_par_file(files, data)

  if (f4mode) {
    write("f4mode: YES", file = files[["par_file"]], append = TRUE)
  }

  # automatically calculate standard errors
  write("printsd: YES", file = files[["par_file"]], append = TRUE)

  run_cmd("qpDstat", par_file = files[["par_file"]], log_file = files[["log_file"]])

  read_output(files[["log_file"]])
}



#' @rdname f4ratio
#'
#' @export
f4 <- function(data, W, X, Y, Z, outdir = NULL) {
  d(data, W, X, Y, Z, outdir, f4mode = TRUE)
}



#' @rdname f4ratio
#'
#' @param inbreed See README.3PopTest in ADMIXTOOLS for an explanation.
#'
#' @export
f3 <- function(data, A, B, C, outdir = NULL, inbreed = FALSE) {
  check_presence(c(A, B, C), data)

  # get the path to the population, parameter and log files
  config_prefix <- paste0("qp3Pop__", as.integer(stats::runif(1, 0, .Machine$integer.max)))
  files <- get_files(outdir, config_prefix)

  create_qp3Pop_pop_file(A, B, C, file = files[["pop_file"]])
  create_par_file(files, data)

  if (inbreed) {
    write("inbreed: YES", file = files[["par_file"]], append = TRUE)
  }

  run_cmd("qp3Pop", par_file = files[["par_file"]], log_file = files[["log_file"]])

  read_output(files[["log_file"]])
}



#' Calculate ancestry proportions in a set of target populations.
#'
#' @param target Vector of target populations (evaluated one at a time).
#' @param sources Source populations related to true ancestors.
#' @param outgroups Outgroup populations.
#' @param details Include detailed information about model fit? Otherwise
#'   return just admixture proportions.
#'
#' @param data EIGENSTRAT data object.
#' @param outdir Where to put all generated files (temporary directory by default).
#'
#' @export
qpAdm <- function(data, target, sources, outgroups, details = TRUE, outdir = NULL) {
  check_presence(c(target, sources, outgroups), data)

  results <- lapply(target, function(X) {
    # get the path to the population, parameter and log files
    config_prefix <- paste0("qpAdm__", as.integer(stats::runif(1, 0, .Machine$integer.max)))
    files <- get_files(outdir, config_prefix)

    files[["popleft"]] <-  stringr::str_replace(files[["pop_file"]], "$", "left")
    files[["popright"]] <-  stringr::str_replace(files[["pop_file"]], "$", "right")
    files[["pop_file"]] <- NULL

    create_leftright_pop_files(c(X, sources), outgroups, files)
    create_par_file(files, data)

    run_cmd("qpAdm", par_file = files[["par_file"]], log_file = files[["log_file"]])

    read_output(files[["log_file"]])
  })

  # process the complex list of lists of dataframes into a more readable form
  # by concatenating all internal dataframes and returning a simple list
  # of three dataframes
  proportions <- dplyr::bind_rows(lapply(results, function(x) x$proportions))
  
  if (details) {
    ranks <- lapply(seq_along(target), function(i) { results[[i]]$ranks %>% dplyr::mutate(target = target[i]) }) %>%
      dplyr::bind_rows() %>%
      dplyr::select(target, dplyr::everything())
    subsets <- lapply(seq_along(target), function(i) {
        results[[i]]$subsets %>% dplyr::mutate(target = target[i])
      }) %>%
      dplyr::bind_rows() %>%
      dplyr::select(target, dplyr::everything())
    return(list(
      proportions = proportions,
      ranks = ranks,
      subsets = subsets
    ))
  } else {
    return(proportions)
  }
}



#' Find the most likely number of ancestry waves using the qpWave method.
#'
#' Given a set of 'left' populations, estimate the lowest number of necessary
#' admixture sources related to the set of 'right' populations.
#'
#' It has been shown (Reich, Nature 2012 - Reconstructing Native American
#' population history) that if the 'left' populations are mixtures of N
#' different sources related to the set of 'right' populations, the rank of the
#' matrix of the form \eqn{f_4(left_i, left_j; right_k, right_l)} will have a
#' rank N - 1. This function uses the ADMIXTOOLS command qpWave to find the
#' lowest possible rank of this matrix that is consistent with the data.
#'
#' @param left,right Character vectors of populations labels.
#' @param maxrank Maximum rank to test for.
#' @param details Return the A, B matrices used in rank calculations?
#' @inheritParams qpAdm
#'
#' @export
qpWave <- function(data, left, right, maxrank = NULL, details = FALSE, outdir = NULL) {
  check_presence(c(left, right), data)
  if (length(intersect(left, right))) {
    stop("Duplicated populations in both left and right population sets not allowed: ",
         paste(intersect(left, right), collapse = " "),
         call. = FALSE)
  }

  # get the path to the population, parameter and log files
  setup <- paste0("qpWave")
  config_prefix <- paste0(setup, "__", as.integer(stats::runif(1, 0, .Machine$integer.max)))
  files <- get_files(outdir, config_prefix)

  files[["popleft"]] <-  stringr::str_replace(files[["pop_file"]], "$", "left")
  files[["popright"]] <-  stringr::str_replace(files[["pop_file"]], "$", "right")
  files[["pop_file"]] <- NULL

  create_leftright_pop_files(left, right, files)
  create_par_file(files, data)

  if (!is.null(maxrank)) {
    write(sprintf("maxrank: %d", maxrank), file = files[["par_file"]], append = TRUE)
  }

  run_cmd("qpWave", par_file = files[["par_file"]], log_file = files[["log_file"]])

  read_output(files[["log_file"]], details)
}

