set -e

if [ "$1" = "p2" ]; then
   ENV_DIR="../p2"
   virtualenv -p python2 "$ENV_DIR"
   echo "Testing python2"
else
   ENV_DIR="../p3"
   virtualenv -p python3 "$ENV_DIR"
   echo "Testing python3"
fi;

#activate environment
. "$ENV_DIR/bin/activate"

#prepare:
pip install cython

if [ "$2" = "from-github" ]; then
    echo "Installing setup.py from github..."
    pip install https://github.com/realead/indirect_buffer/zipball/master
else
    echo "Installing local setup.py..."
    (cd .. && python setup.py install)
fi;

pip install numpy

echo "Installed packages:"
pip freeze


echo "Running unit tests:"
sh run_unit_tests.sh



#clean or keep the environment
if [ "$3" = "keep" ]; then
   echo "keeping enviroment $ENV_DIR"
else
   rm -r "$ENV_DIR"
   rm -r unit_tests/temp_builds
fi;

