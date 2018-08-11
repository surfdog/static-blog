docker run --rm -it -v $PWD:/src -p 1313:1313 -u hugo hugo git submodule update --init && hugo server --bind 0.0.0.0
