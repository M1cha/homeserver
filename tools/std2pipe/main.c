#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/sendfile.h>
#include <unistd.h>

#define LOG_ERROR(fmt, ...) fprintf(stderr, fmt "\n", ##__VA_ARGS__)

#define LOG_ERRNO(fmt, ...) \
    do { \
        const int errno_ = errno; \
        LOG_ERROR(fmt " errno=%d: %s", ##__VA_ARGS__, errno_, strerror(errno_)); \
    } while (0)

struct epoll_event_ctx {
    int source;
    int destination;
};

static uint8_t buf[1024];

static int set_nonblocking(const int fd)
{
    const int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) {
        LOG_ERROR("F_GETFL failed");
        return flags;
    }
    if (flags & O_NONBLOCK) {
        return 0;
    }

    const int ret = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    if (ret) {
        LOG_ERROR("F_SETFL failed");
        return ret;
    }

    return 0;
}

int main(int argc, char** argv)
{
    int ret;
    int pipefd[2];
    struct epoll_event event;

    if (argc < 2) {
        LOG_ERROR("missing program argument");
        return 1;
    }
    argc -= 1;
    argv += 1;

    ret = pipe(pipefd);
    if (ret) {
        LOG_ERRNO("failed to create stdout pipe");
        return 1;
    }
    const int pipe_out_read = pipefd[0];
    const int pipe_out_write = pipefd[1];

    ret = pipe(pipefd);
    if (ret) {
        LOG_ERRNO("failed to create stderr pipe");
        return 1;
    }
    const int pipe_err_read = pipefd[0];
    const int pipe_err_write = pipefd[1];

    const pid_t pid = fork();
    if (pid < 0) {
        LOG_ERRNO("failed to fork");
        return 1;
    }

    // parent
    if (pid != 0) {
        close(pipe_out_read);
        close(pipe_err_read);

        ret = dup2(pipe_out_write, STDOUT_FILENO);
        if (ret != STDOUT_FILENO) {
            LOG_ERRNO("failed dup2 stdout ret=%d", ret);
            _exit(1);
            return 1;
        }

        ret = dup2(pipe_err_write, STDERR_FILENO);
        if (ret != STDERR_FILENO) {
            LOG_ERRNO("failed to dup2 stderr ret=%d", ret);
            _exit(1);
            return 1;
        }

        errno = 0;
        ret = execvp(argv[0], argv);

        LOG_ERRNO("exec failed ret=%d", ret);
        _exit(1);
        return 1;
    }

    // child
    close(pipe_out_write);
    close(pipe_err_write);

    ret = set_nonblocking(pipe_out_read);
    if (ret) {
        return 1;
    }

    ret = set_nonblocking(pipe_err_read);
    if (ret) {
        return 1;
    }

    const int epoll_instance = epoll_create1(0);
    if (epoll_instance < 0) {
        LOG_ERRNO("epoll_create1 failed");
        return 1;
    }

    // tracks how many fds are in the wpoll set so we can quit when it's empty
    int num_epoll_fds = 0;

    event = (struct epoll_event) {
        .events = EPOLLIN | EPOLLRDHUP,
        .data = {
            .ptr = &(struct epoll_event_ctx) {
                .source = pipe_out_read,
                .destination = STDOUT_FILENO,
            },
        },
    };
    ret = epoll_ctl(epoll_instance, EPOLL_CTL_ADD, pipe_out_read, &event);
    if (ret) {
        LOG_ERRNO("failed to add out pipe to epoll instance");
        return 1;
    }
    num_epoll_fds += 1;

    event = (struct epoll_event) {
        .events = EPOLLIN | EPOLLRDHUP,
        .data = {
            .ptr = &(struct epoll_event_ctx) {
                .source = pipe_err_read,
                .destination = STDERR_FILENO,
            },
        },
    };
    ret = epoll_ctl(epoll_instance, EPOLL_CTL_ADD, pipe_err_read, &event);
    if (ret) {
        LOG_ERRNO("failed to add err pipe to epoll instance");
        return 1;
    }
    num_epoll_fds += 1;

    while (num_epoll_fds > 0) {
        ret = epoll_wait(epoll_instance, &event, 1, -1);
        if (ret < 0) {
            if (errno == EINTR) {
                continue;
            }

            LOG_ERRNO("epoll_wait failed");
            return 1;
        } else if (ret == 0) {
            continue;
        } else if (ret > 1) {
            LOG_ERRNO("epoll_wait returned more events than requested");
            return 1;
        }
        const struct epoll_event_ctx* const context = event.data.ptr;

        if (event.events & (EPOLLRDHUP | EPOLLHUP)) {
            ret = epoll_ctl(epoll_instance, EPOLL_CTL_DEL, context->source, NULL);
            if (ret) {
                LOG_ERRNO("failed to remove pipe from epoll instance");
                return 1;
            }
            num_epoll_fds -= 1;
        } else if (event.events & EPOLLERR) {
            LOG_ERROR("epoll_wait returned errors. events=0x%" PRIx32, event.events);
            return 1;
        }

        const ssize_t num_read_ = read(context->source, buf, sizeof(buf));
        if (num_read_ < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                continue;
            }

            LOG_ERRNO("read failed");
            return 1;
        } else if (num_read_ == 0) {
            // the process terminated
            break;
        }
        const size_t num_read = (size_t)num_read_;

        size_t total_written = 0;
        while (num_read > total_written) {
            const ssize_t num_written_ = write(
                context->destination, &buf[total_written], num_read - total_written);
            if (num_written_ < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                    continue;
                }

                LOG_ERRNO("write failed");
                return 1;
            } else if (num_written_ == 0) {
                // receiver side was closed
                break;
            }
            const size_t num_written = (size_t)num_written_;

            total_written += num_written;
        }
    }

    return 0;
}
