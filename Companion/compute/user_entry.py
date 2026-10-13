import runpy
import assistant

# The tool contract exposes this helper directly. Keep normal imports working
# too; each execution loads its own request and never shares Python globals.
runpy.run_path('/task/code.py', init_globals={'assistant': assistant}, run_name='__main__')
