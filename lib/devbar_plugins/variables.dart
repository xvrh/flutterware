export '../src/devbar/plugins/variables/add_variable.dart'
    show AddDevbarVariable;
export '../src/devbar/plugins/variables/file_store.dart' show FileVariableStore;
export '../src/devbar/plugins/variables/plugin.dart'
    show VariablesPlugin, VariablesPluginDevbarExtension, DevbarVariable;
// `VariablesPlugin.init` takes a `store:` and a `storeFactory:`, so the type
// they take is part of the surface whether or not it is exported. It was not,
// and a consumer wanting to keep its own values somewhere reached into `src/`
// to name it — which is the report that put this line here.
export '../src/devbar/plugins/variables/store.dart'
    show InMemoryVariablesStore, VariablesStore;
