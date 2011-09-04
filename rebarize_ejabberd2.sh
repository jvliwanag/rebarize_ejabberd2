#!/bin/bash

if [ $# -lt 1 ]; then
	echo "Usage $0 ejabberd_dir"
	exit 1 
fi

base_dir=$1

cd $base_dir/src

src_dir=.
include_dir=../include
asn1s_dir=../asn1
c_src_dir=../c_src
lib_dir=../priv/lib
config_dir=../config

erl_opts="[{d, 'SSL40'}]"

# Move *.hrl to include
mkdir $include_dir 2> /dev/null
hrls=`find . -name '*.hrl'`
for hrl in $hrls; do
    hrl_dir=`dirname $hrl`
    mkdir "$include_dir"/"$hrl_dir" 2> /dev/null
    mv $hrl $include_dir/$hrl
done

# Move *.ans1 to asn1
mkdir $asn1s_dir 2> /dev/null
asn1s=`find . -name '*.asn1'`
mv $asn1s  $asn1s_dir

asns=`find . -name '*.asn'`
for asn in $asns; do
    asn1_name="`basename $asn`1"
    mv $asn $asn1s_dir/$asn1_name
done

# Move *.h to c_src
mkdir $c_src_dir 2> /dev/null

hs=`find . -name '*.h'`
mv $hs $c_src_dir


## TODO xml.c doesn't seem to work
rm xml.c

cs=`find . -name '*.c'`
mv $cs $c_src_dir

# Ready lib dir
mkdir -p $lib_dir 2> /dev/null

## Assemble rebar.config
rebar_config=../rebar.config
touch $rebar_config

# Add erl_opts to rebar.config
cd ..
find include -type d | xargs erl -eval "io:format(\"~p.~n~n\", [{erl_opts, $erl_opts ++ [{i, I} || I <- init:get_plain_arguments()]}]),erlang:halt()." -noshell -extra >> rebar.config
cd src

# Add so_specs to rebar.config
cd ../c_src
find * -name '*.c' | xargs erl -eval 'io:format("~p.~n~n", [{so_specs, [{"priv/lib/" ++ re:replace(X, "\\.c$", ".so", [{return, list}]), ["c_src/" ++ re:replace(X, "\\.c$", ".o", [{return, list}])]} || X <- init:get_plain_arguments()]}]), erlang:halt().' -noshell -extra >> ../rebar.config
cd ../src


# Add port_envs to rebar.config
echo '{port_envs, [{"LDFLAGS", "$LDFLAGS -lz -liconv -lexpat -lssl -lcrypto"}]}.' >> ../rebar.config

# ejabberdctl

ejabberdctl=../ejabberdctl
cp ejabberdctl.template $ejabberdctl

sed -i "" '3i\
BASEDIR=$(cd $(dirname $(dirname $0)); pwd)
' $ejabberdctl

sed -i "" -e 's/@erl@/erl/' \
    -e 's/@installuser@/$USER/' \
    -e 's/ETCDIR=@SYSCONFDIR@\/ejabberd/ETCDIR=$BASEDIR\/config/' \
    -e 's/LOGS_DIR=@LOCALSTATEDIR@\/log\/ejabberd/LOGS_DIR=$BASEDIR\/log/' \
    -e 's/SPOOLDIR=@LOCALSTATEDIR@\/lib\/ejabberd/SPOOLDIR=$BASEDIR\/spool/' \
    -e 's/EJABBERD_DOC_PATH=@DOCDIR@/EJABBERD_DOC_PATH=$BASEDIR\/docs/' \
    -e 's/EJABBERDDIR=@LIBDIR@\/ejabberd/EJABBERDDIR=$BASEDIR/' \
    -e 's/CONNLOCKDIR=@LOCALSTATEDIR@\/lock\/ejabberdctl/$BASEDIR\/lock\/ejabberdctl/' \
    $ejabberdctl

chmod +x $ejabberdctl

# inetrc, ejabberd.cfg, ejabberdctl.cfg
mkdir $config_dir 2> /dev/null
mv inetrc $config_dir
cp ejabberd.cfg.example $config_dir/ejabberd.cfg
cp ejabberdctl.cfg.example $config_dir/ejabberdctl.cfg

# copy your rebar
cp `which rebar` ..

tee ../Makefile >/dev/null <<EOF
ERL ?= erl
APP := vokka_web

.PHONY: deps

all: deps
	@./rebar compile

deps:
	@./rebar get-deps

clean:
	@./rebar clean

distclean: clean
	@./rebar delete-deps

docs:
	@erl -noshell -run edoc_run application '\$(APP)' '"."' '[]'
EOF
