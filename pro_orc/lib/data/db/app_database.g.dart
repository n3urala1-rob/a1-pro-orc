// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppConfigTableTable extends AppConfigTable
    with TableInfo<$AppConfigTableTable, AppConfigTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppConfigTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _scanDirMeta = const VerificationMeta(
    'scanDir',
  );
  @override
  late final GeneratedColumn<String> scanDir = GeneratedColumn<String>(
    'scan_dir',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _ignoreListJsonMeta = const VerificationMeta(
    'ignoreListJson',
  );
  @override
  late final GeneratedColumn<String> ignoreListJson = GeneratedColumn<String>(
    'ignore_list_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[".*","node_modules","build",".dart_tool"]'),
  );
  static const VerificationMeta _gitBinaryPathMeta = const VerificationMeta(
    'gitBinaryPath',
  );
  @override
  late final GeneratedColumn<String> gitBinaryPath = GeneratedColumn<String>(
    'git_binary_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('git'),
  );
  static const VerificationMeta _themeModeMeta = const VerificationMeta(
    'themeMode',
  );
  @override
  late final GeneratedColumn<String> themeMode = GeneratedColumn<String>(
    'theme_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('dark'),
  );
  static const VerificationMeta _vaultDirMeta = const VerificationMeta(
    'vaultDir',
  );
  @override
  late final GeneratedColumn<String> vaultDir = GeneratedColumn<String>(
    'vault_dir',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _viewModeMeta = const VerificationMeta(
    'viewMode',
  );
  @override
  late final GeneratedColumn<String> viewMode = GeneratedColumn<String>(
    'view_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('grid'),
  );
  static const VerificationMeta _projectOrganizationSeedAppliedMeta =
      const VerificationMeta('projectOrganizationSeedApplied');
  @override
  late final GeneratedColumn<bool> projectOrganizationSeedApplied =
      GeneratedColumn<bool>(
        'project_organization_seed_applied',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("project_organization_seed_applied" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _vaultHubFolderMeta = const VerificationMeta(
    'vaultHubFolder',
  );
  @override
  late final GeneratedColumn<String> vaultHubFolder = GeneratedColumn<String>(
    'vault_hub_folder',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('project'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    scanDir,
    ignoreListJson,
    gitBinaryPath,
    themeMode,
    vaultDir,
    viewMode,
    projectOrganizationSeedApplied,
    vaultHubFolder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_config_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppConfigTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('scan_dir')) {
      context.handle(
        _scanDirMeta,
        scanDir.isAcceptableOrUnknown(data['scan_dir']!, _scanDirMeta),
      );
    }
    if (data.containsKey('ignore_list_json')) {
      context.handle(
        _ignoreListJsonMeta,
        ignoreListJson.isAcceptableOrUnknown(
          data['ignore_list_json']!,
          _ignoreListJsonMeta,
        ),
      );
    }
    if (data.containsKey('git_binary_path')) {
      context.handle(
        _gitBinaryPathMeta,
        gitBinaryPath.isAcceptableOrUnknown(
          data['git_binary_path']!,
          _gitBinaryPathMeta,
        ),
      );
    }
    if (data.containsKey('theme_mode')) {
      context.handle(
        _themeModeMeta,
        themeMode.isAcceptableOrUnknown(data['theme_mode']!, _themeModeMeta),
      );
    }
    if (data.containsKey('vault_dir')) {
      context.handle(
        _vaultDirMeta,
        vaultDir.isAcceptableOrUnknown(data['vault_dir']!, _vaultDirMeta),
      );
    }
    if (data.containsKey('view_mode')) {
      context.handle(
        _viewModeMeta,
        viewMode.isAcceptableOrUnknown(data['view_mode']!, _viewModeMeta),
      );
    }
    if (data.containsKey('project_organization_seed_applied')) {
      context.handle(
        _projectOrganizationSeedAppliedMeta,
        projectOrganizationSeedApplied.isAcceptableOrUnknown(
          data['project_organization_seed_applied']!,
          _projectOrganizationSeedAppliedMeta,
        ),
      );
    }
    if (data.containsKey('vault_hub_folder')) {
      context.handle(
        _vaultHubFolderMeta,
        vaultHubFolder.isAcceptableOrUnknown(
          data['vault_hub_folder']!,
          _vaultHubFolderMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppConfigTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppConfigTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      scanDir: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scan_dir'],
      )!,
      ignoreListJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ignore_list_json'],
      )!,
      gitBinaryPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}git_binary_path'],
      )!,
      themeMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_mode'],
      )!,
      vaultDir: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vault_dir'],
      )!,
      viewMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}view_mode'],
      )!,
      projectOrganizationSeedApplied: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}project_organization_seed_applied'],
      )!,
      vaultHubFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vault_hub_folder'],
      )!,
    );
  }

  @override
  $AppConfigTableTable createAlias(String alias) {
    return $AppConfigTableTable(attachedDatabase, alias);
  }
}

class AppConfigTableData extends DataClass
    implements Insertable<AppConfigTableData> {
  final int id;
  final String scanDir;
  final String ignoreListJson;
  final String gitBinaryPath;

  /// One of 'light', 'dark', 'system'. Default 'dark' preserves the existing
  /// look for current users (v2.2 Design-Refresh).
  final String themeMode;

  /// Absolute path to the Obsidian vault root used for the a1 learning-loop
  /// view (M6). Empty string means "use the default" (`$HOME/N3URAL-Vault`),
  /// resolved by the reader — kept empty by default so per-machine HOME is not
  /// baked into the DB.
  final String vaultDir;

  /// Global grid/list view-mode preference for the Projekte tab: 'grid' or
  /// 'list'. Default 'grid' preserves the current look for existing users.
  final String viewMode;

  /// One-time idempotency flag for the Project-Organization example-group
  /// seed (Wave 5). Independent of `ensureSystemGroups` — the Archiv system
  /// group exists regardless of this flag.
  final bool projectOrganizationSeedApplied;

  /// Folder convention within [vaultDir] for project hubs (7-type-IA style),
  /// e.g. 'project' for `project/<slug>.md`. Empty/default resolves to
  /// 'project' — kept as an explicit column (not hardcoded) so the folder
  /// name is user-configurable if their vault uses a different convention.
  final String vaultHubFolder;
  const AppConfigTableData({
    required this.id,
    required this.scanDir,
    required this.ignoreListJson,
    required this.gitBinaryPath,
    required this.themeMode,
    required this.vaultDir,
    required this.viewMode,
    required this.projectOrganizationSeedApplied,
    required this.vaultHubFolder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['scan_dir'] = Variable<String>(scanDir);
    map['ignore_list_json'] = Variable<String>(ignoreListJson);
    map['git_binary_path'] = Variable<String>(gitBinaryPath);
    map['theme_mode'] = Variable<String>(themeMode);
    map['vault_dir'] = Variable<String>(vaultDir);
    map['view_mode'] = Variable<String>(viewMode);
    map['project_organization_seed_applied'] = Variable<bool>(
      projectOrganizationSeedApplied,
    );
    map['vault_hub_folder'] = Variable<String>(vaultHubFolder);
    return map;
  }

  AppConfigTableCompanion toCompanion(bool nullToAbsent) {
    return AppConfigTableCompanion(
      id: Value(id),
      scanDir: Value(scanDir),
      ignoreListJson: Value(ignoreListJson),
      gitBinaryPath: Value(gitBinaryPath),
      themeMode: Value(themeMode),
      vaultDir: Value(vaultDir),
      viewMode: Value(viewMode),
      projectOrganizationSeedApplied: Value(projectOrganizationSeedApplied),
      vaultHubFolder: Value(vaultHubFolder),
    );
  }

  factory AppConfigTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppConfigTableData(
      id: serializer.fromJson<int>(json['id']),
      scanDir: serializer.fromJson<String>(json['scanDir']),
      ignoreListJson: serializer.fromJson<String>(json['ignoreListJson']),
      gitBinaryPath: serializer.fromJson<String>(json['gitBinaryPath']),
      themeMode: serializer.fromJson<String>(json['themeMode']),
      vaultDir: serializer.fromJson<String>(json['vaultDir']),
      viewMode: serializer.fromJson<String>(json['viewMode']),
      projectOrganizationSeedApplied: serializer.fromJson<bool>(
        json['projectOrganizationSeedApplied'],
      ),
      vaultHubFolder: serializer.fromJson<String>(json['vaultHubFolder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'scanDir': serializer.toJson<String>(scanDir),
      'ignoreListJson': serializer.toJson<String>(ignoreListJson),
      'gitBinaryPath': serializer.toJson<String>(gitBinaryPath),
      'themeMode': serializer.toJson<String>(themeMode),
      'vaultDir': serializer.toJson<String>(vaultDir),
      'viewMode': serializer.toJson<String>(viewMode),
      'projectOrganizationSeedApplied': serializer.toJson<bool>(
        projectOrganizationSeedApplied,
      ),
      'vaultHubFolder': serializer.toJson<String>(vaultHubFolder),
    };
  }

  AppConfigTableData copyWith({
    int? id,
    String? scanDir,
    String? ignoreListJson,
    String? gitBinaryPath,
    String? themeMode,
    String? vaultDir,
    String? viewMode,
    bool? projectOrganizationSeedApplied,
    String? vaultHubFolder,
  }) => AppConfigTableData(
    id: id ?? this.id,
    scanDir: scanDir ?? this.scanDir,
    ignoreListJson: ignoreListJson ?? this.ignoreListJson,
    gitBinaryPath: gitBinaryPath ?? this.gitBinaryPath,
    themeMode: themeMode ?? this.themeMode,
    vaultDir: vaultDir ?? this.vaultDir,
    viewMode: viewMode ?? this.viewMode,
    projectOrganizationSeedApplied:
        projectOrganizationSeedApplied ?? this.projectOrganizationSeedApplied,
    vaultHubFolder: vaultHubFolder ?? this.vaultHubFolder,
  );
  AppConfigTableData copyWithCompanion(AppConfigTableCompanion data) {
    return AppConfigTableData(
      id: data.id.present ? data.id.value : this.id,
      scanDir: data.scanDir.present ? data.scanDir.value : this.scanDir,
      ignoreListJson: data.ignoreListJson.present
          ? data.ignoreListJson.value
          : this.ignoreListJson,
      gitBinaryPath: data.gitBinaryPath.present
          ? data.gitBinaryPath.value
          : this.gitBinaryPath,
      themeMode: data.themeMode.present ? data.themeMode.value : this.themeMode,
      vaultDir: data.vaultDir.present ? data.vaultDir.value : this.vaultDir,
      viewMode: data.viewMode.present ? data.viewMode.value : this.viewMode,
      projectOrganizationSeedApplied:
          data.projectOrganizationSeedApplied.present
          ? data.projectOrganizationSeedApplied.value
          : this.projectOrganizationSeedApplied,
      vaultHubFolder: data.vaultHubFolder.present
          ? data.vaultHubFolder.value
          : this.vaultHubFolder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppConfigTableData(')
          ..write('id: $id, ')
          ..write('scanDir: $scanDir, ')
          ..write('ignoreListJson: $ignoreListJson, ')
          ..write('gitBinaryPath: $gitBinaryPath, ')
          ..write('themeMode: $themeMode, ')
          ..write('vaultDir: $vaultDir, ')
          ..write('viewMode: $viewMode, ')
          ..write(
            'projectOrganizationSeedApplied: $projectOrganizationSeedApplied, ',
          )
          ..write('vaultHubFolder: $vaultHubFolder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    scanDir,
    ignoreListJson,
    gitBinaryPath,
    themeMode,
    vaultDir,
    viewMode,
    projectOrganizationSeedApplied,
    vaultHubFolder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppConfigTableData &&
          other.id == this.id &&
          other.scanDir == this.scanDir &&
          other.ignoreListJson == this.ignoreListJson &&
          other.gitBinaryPath == this.gitBinaryPath &&
          other.themeMode == this.themeMode &&
          other.vaultDir == this.vaultDir &&
          other.viewMode == this.viewMode &&
          other.projectOrganizationSeedApplied ==
              this.projectOrganizationSeedApplied &&
          other.vaultHubFolder == this.vaultHubFolder);
}

class AppConfigTableCompanion extends UpdateCompanion<AppConfigTableData> {
  final Value<int> id;
  final Value<String> scanDir;
  final Value<String> ignoreListJson;
  final Value<String> gitBinaryPath;
  final Value<String> themeMode;
  final Value<String> vaultDir;
  final Value<String> viewMode;
  final Value<bool> projectOrganizationSeedApplied;
  final Value<String> vaultHubFolder;
  const AppConfigTableCompanion({
    this.id = const Value.absent(),
    this.scanDir = const Value.absent(),
    this.ignoreListJson = const Value.absent(),
    this.gitBinaryPath = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.vaultDir = const Value.absent(),
    this.viewMode = const Value.absent(),
    this.projectOrganizationSeedApplied = const Value.absent(),
    this.vaultHubFolder = const Value.absent(),
  });
  AppConfigTableCompanion.insert({
    this.id = const Value.absent(),
    this.scanDir = const Value.absent(),
    this.ignoreListJson = const Value.absent(),
    this.gitBinaryPath = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.vaultDir = const Value.absent(),
    this.viewMode = const Value.absent(),
    this.projectOrganizationSeedApplied = const Value.absent(),
    this.vaultHubFolder = const Value.absent(),
  });
  static Insertable<AppConfigTableData> custom({
    Expression<int>? id,
    Expression<String>? scanDir,
    Expression<String>? ignoreListJson,
    Expression<String>? gitBinaryPath,
    Expression<String>? themeMode,
    Expression<String>? vaultDir,
    Expression<String>? viewMode,
    Expression<bool>? projectOrganizationSeedApplied,
    Expression<String>? vaultHubFolder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scanDir != null) 'scan_dir': scanDir,
      if (ignoreListJson != null) 'ignore_list_json': ignoreListJson,
      if (gitBinaryPath != null) 'git_binary_path': gitBinaryPath,
      if (themeMode != null) 'theme_mode': themeMode,
      if (vaultDir != null) 'vault_dir': vaultDir,
      if (viewMode != null) 'view_mode': viewMode,
      if (projectOrganizationSeedApplied != null)
        'project_organization_seed_applied': projectOrganizationSeedApplied,
      if (vaultHubFolder != null) 'vault_hub_folder': vaultHubFolder,
    });
  }

  AppConfigTableCompanion copyWith({
    Value<int>? id,
    Value<String>? scanDir,
    Value<String>? ignoreListJson,
    Value<String>? gitBinaryPath,
    Value<String>? themeMode,
    Value<String>? vaultDir,
    Value<String>? viewMode,
    Value<bool>? projectOrganizationSeedApplied,
    Value<String>? vaultHubFolder,
  }) {
    return AppConfigTableCompanion(
      id: id ?? this.id,
      scanDir: scanDir ?? this.scanDir,
      ignoreListJson: ignoreListJson ?? this.ignoreListJson,
      gitBinaryPath: gitBinaryPath ?? this.gitBinaryPath,
      themeMode: themeMode ?? this.themeMode,
      vaultDir: vaultDir ?? this.vaultDir,
      viewMode: viewMode ?? this.viewMode,
      projectOrganizationSeedApplied:
          projectOrganizationSeedApplied ?? this.projectOrganizationSeedApplied,
      vaultHubFolder: vaultHubFolder ?? this.vaultHubFolder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (scanDir.present) {
      map['scan_dir'] = Variable<String>(scanDir.value);
    }
    if (ignoreListJson.present) {
      map['ignore_list_json'] = Variable<String>(ignoreListJson.value);
    }
    if (gitBinaryPath.present) {
      map['git_binary_path'] = Variable<String>(gitBinaryPath.value);
    }
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(themeMode.value);
    }
    if (vaultDir.present) {
      map['vault_dir'] = Variable<String>(vaultDir.value);
    }
    if (viewMode.present) {
      map['view_mode'] = Variable<String>(viewMode.value);
    }
    if (projectOrganizationSeedApplied.present) {
      map['project_organization_seed_applied'] = Variable<bool>(
        projectOrganizationSeedApplied.value,
      );
    }
    if (vaultHubFolder.present) {
      map['vault_hub_folder'] = Variable<String>(vaultHubFolder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppConfigTableCompanion(')
          ..write('id: $id, ')
          ..write('scanDir: $scanDir, ')
          ..write('ignoreListJson: $ignoreListJson, ')
          ..write('gitBinaryPath: $gitBinaryPath, ')
          ..write('themeMode: $themeMode, ')
          ..write('vaultDir: $vaultDir, ')
          ..write('viewMode: $viewMode, ')
          ..write(
            'projectOrganizationSeedApplied: $projectOrganizationSeedApplied, ',
          )
          ..write('vaultHubFolder: $vaultHubFolder')
          ..write(')'))
        .toString();
  }
}

class $ProjectSettingsTableTable extends ProjectSettingsTable
    with TableInfo<$ProjectSettingsTableTable, ProjectSettingsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectTypeMeta = const VerificationMeta(
    'projectType',
  );
  @override
  late final GeneratedColumn<String> projectType = GeneratedColumn<String>(
    'project_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeSetAtMeta = const VerificationMeta(
    'typeSetAt',
  );
  @override
  late final GeneratedColumn<DateTime> typeSetAt = GeneratedColumn<DateTime>(
    'type_set_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isHiddenMeta = const VerificationMeta(
    'isHidden',
  );
  @override
  late final GeneratedColumn<bool> isHidden = GeneratedColumn<bool>(
    'is_hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vaultHubSlugMeta = const VerificationMeta(
    'vaultHubSlug',
  );
  @override
  late final GeneratedColumn<String> vaultHubSlug = GeneratedColumn<String>(
    'vault_hub_slug',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vaultLastSyncAtMeta = const VerificationMeta(
    'vaultLastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> vaultLastSyncAt =
      GeneratedColumn<DateTime>(
        'vault_last_sync_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    folderId,
    projectType,
    displayName,
    typeSetAt,
    isHidden,
    groupId,
    vaultHubSlug,
    vaultLastSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_settings_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectSettingsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_folderIdMeta);
    }
    if (data.containsKey('project_type')) {
      context.handle(
        _projectTypeMeta,
        projectType.isAcceptableOrUnknown(
          data['project_type']!,
          _projectTypeMeta,
        ),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('type_set_at')) {
      context.handle(
        _typeSetAtMeta,
        typeSetAt.isAcceptableOrUnknown(data['type_set_at']!, _typeSetAtMeta),
      );
    }
    if (data.containsKey('is_hidden')) {
      context.handle(
        _isHiddenMeta,
        isHidden.isAcceptableOrUnknown(data['is_hidden']!, _isHiddenMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('vault_hub_slug')) {
      context.handle(
        _vaultHubSlugMeta,
        vaultHubSlug.isAcceptableOrUnknown(
          data['vault_hub_slug']!,
          _vaultHubSlugMeta,
        ),
      );
    }
    if (data.containsKey('vault_last_sync_at')) {
      context.handle(
        _vaultLastSyncAtMeta,
        vaultLastSyncAt.isAcceptableOrUnknown(
          data['vault_last_sync_at']!,
          _vaultLastSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {folderId};
  @override
  ProjectSettingsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectSettingsTableData(
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      )!,
      projectType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_type'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      typeSetAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}type_set_at'],
      ),
      isHidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_hidden'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      vaultHubSlug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vault_hub_slug'],
      ),
      vaultLastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}vault_last_sync_at'],
      ),
    );
  }

  @override
  $ProjectSettingsTableTable createAlias(String alias) {
    return $ProjectSettingsTableTable(attachedDatabase, alias);
  }
}

class ProjectSettingsTableData extends DataClass
    implements Insertable<ProjectSettingsTableData> {
  final String folderId;
  final String? projectType;
  final String? displayName;
  final DateTime? typeSetAt;
  final bool isHidden;
  final String? groupId;

  /// Confirmed vault hub filename stem this project is linked to (e.g.
  /// 'pro-orc' for project/pro-orc.md), relative to vaultDir/vaultHubFolder.
  /// Null = not yet linked (fuzzy-match-or-auto-create path still applies).
  final String? vaultHubSlug;

  /// Timestamp of the last AUTOMATIC vault write for this project (the
  /// automatic-write debounce interval enforced in Wave 3 reads this).
  /// Manual "Jetzt synchronisieren" writes (added in Wave 4) also update
  /// this column so a manual write resets the debounce window, preventing
  /// an automatic write from firing immediately after.
  final DateTime? vaultLastSyncAt;
  const ProjectSettingsTableData({
    required this.folderId,
    this.projectType,
    this.displayName,
    this.typeSetAt,
    required this.isHidden,
    this.groupId,
    this.vaultHubSlug,
    this.vaultLastSyncAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['folder_id'] = Variable<String>(folderId);
    if (!nullToAbsent || projectType != null) {
      map['project_type'] = Variable<String>(projectType);
    }
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || typeSetAt != null) {
      map['type_set_at'] = Variable<DateTime>(typeSetAt);
    }
    map['is_hidden'] = Variable<bool>(isHidden);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    if (!nullToAbsent || vaultHubSlug != null) {
      map['vault_hub_slug'] = Variable<String>(vaultHubSlug);
    }
    if (!nullToAbsent || vaultLastSyncAt != null) {
      map['vault_last_sync_at'] = Variable<DateTime>(vaultLastSyncAt);
    }
    return map;
  }

  ProjectSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return ProjectSettingsTableCompanion(
      folderId: Value(folderId),
      projectType: projectType == null && nullToAbsent
          ? const Value.absent()
          : Value(projectType),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      typeSetAt: typeSetAt == null && nullToAbsent
          ? const Value.absent()
          : Value(typeSetAt),
      isHidden: Value(isHidden),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      vaultHubSlug: vaultHubSlug == null && nullToAbsent
          ? const Value.absent()
          : Value(vaultHubSlug),
      vaultLastSyncAt: vaultLastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(vaultLastSyncAt),
    );
  }

  factory ProjectSettingsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectSettingsTableData(
      folderId: serializer.fromJson<String>(json['folderId']),
      projectType: serializer.fromJson<String?>(json['projectType']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      typeSetAt: serializer.fromJson<DateTime?>(json['typeSetAt']),
      isHidden: serializer.fromJson<bool>(json['isHidden']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      vaultHubSlug: serializer.fromJson<String?>(json['vaultHubSlug']),
      vaultLastSyncAt: serializer.fromJson<DateTime?>(json['vaultLastSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'folderId': serializer.toJson<String>(folderId),
      'projectType': serializer.toJson<String?>(projectType),
      'displayName': serializer.toJson<String?>(displayName),
      'typeSetAt': serializer.toJson<DateTime?>(typeSetAt),
      'isHidden': serializer.toJson<bool>(isHidden),
      'groupId': serializer.toJson<String?>(groupId),
      'vaultHubSlug': serializer.toJson<String?>(vaultHubSlug),
      'vaultLastSyncAt': serializer.toJson<DateTime?>(vaultLastSyncAt),
    };
  }

  ProjectSettingsTableData copyWith({
    String? folderId,
    Value<String?> projectType = const Value.absent(),
    Value<String?> displayName = const Value.absent(),
    Value<DateTime?> typeSetAt = const Value.absent(),
    bool? isHidden,
    Value<String?> groupId = const Value.absent(),
    Value<String?> vaultHubSlug = const Value.absent(),
    Value<DateTime?> vaultLastSyncAt = const Value.absent(),
  }) => ProjectSettingsTableData(
    folderId: folderId ?? this.folderId,
    projectType: projectType.present ? projectType.value : this.projectType,
    displayName: displayName.present ? displayName.value : this.displayName,
    typeSetAt: typeSetAt.present ? typeSetAt.value : this.typeSetAt,
    isHidden: isHidden ?? this.isHidden,
    groupId: groupId.present ? groupId.value : this.groupId,
    vaultHubSlug: vaultHubSlug.present ? vaultHubSlug.value : this.vaultHubSlug,
    vaultLastSyncAt: vaultLastSyncAt.present
        ? vaultLastSyncAt.value
        : this.vaultLastSyncAt,
  );
  ProjectSettingsTableData copyWithCompanion(
    ProjectSettingsTableCompanion data,
  ) {
    return ProjectSettingsTableData(
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      projectType: data.projectType.present
          ? data.projectType.value
          : this.projectType,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      typeSetAt: data.typeSetAt.present ? data.typeSetAt.value : this.typeSetAt,
      isHidden: data.isHidden.present ? data.isHidden.value : this.isHidden,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      vaultHubSlug: data.vaultHubSlug.present
          ? data.vaultHubSlug.value
          : this.vaultHubSlug,
      vaultLastSyncAt: data.vaultLastSyncAt.present
          ? data.vaultLastSyncAt.value
          : this.vaultLastSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectSettingsTableData(')
          ..write('folderId: $folderId, ')
          ..write('projectType: $projectType, ')
          ..write('displayName: $displayName, ')
          ..write('typeSetAt: $typeSetAt, ')
          ..write('isHidden: $isHidden, ')
          ..write('groupId: $groupId, ')
          ..write('vaultHubSlug: $vaultHubSlug, ')
          ..write('vaultLastSyncAt: $vaultLastSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    folderId,
    projectType,
    displayName,
    typeSetAt,
    isHidden,
    groupId,
    vaultHubSlug,
    vaultLastSyncAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectSettingsTableData &&
          other.folderId == this.folderId &&
          other.projectType == this.projectType &&
          other.displayName == this.displayName &&
          other.typeSetAt == this.typeSetAt &&
          other.isHidden == this.isHidden &&
          other.groupId == this.groupId &&
          other.vaultHubSlug == this.vaultHubSlug &&
          other.vaultLastSyncAt == this.vaultLastSyncAt);
}

class ProjectSettingsTableCompanion
    extends UpdateCompanion<ProjectSettingsTableData> {
  final Value<String> folderId;
  final Value<String?> projectType;
  final Value<String?> displayName;
  final Value<DateTime?> typeSetAt;
  final Value<bool> isHidden;
  final Value<String?> groupId;
  final Value<String?> vaultHubSlug;
  final Value<DateTime?> vaultLastSyncAt;
  final Value<int> rowid;
  const ProjectSettingsTableCompanion({
    this.folderId = const Value.absent(),
    this.projectType = const Value.absent(),
    this.displayName = const Value.absent(),
    this.typeSetAt = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.groupId = const Value.absent(),
    this.vaultHubSlug = const Value.absent(),
    this.vaultLastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectSettingsTableCompanion.insert({
    required String folderId,
    this.projectType = const Value.absent(),
    this.displayName = const Value.absent(),
    this.typeSetAt = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.groupId = const Value.absent(),
    this.vaultHubSlug = const Value.absent(),
    this.vaultLastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : folderId = Value(folderId);
  static Insertable<ProjectSettingsTableData> custom({
    Expression<String>? folderId,
    Expression<String>? projectType,
    Expression<String>? displayName,
    Expression<DateTime>? typeSetAt,
    Expression<bool>? isHidden,
    Expression<String>? groupId,
    Expression<String>? vaultHubSlug,
    Expression<DateTime>? vaultLastSyncAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (folderId != null) 'folder_id': folderId,
      if (projectType != null) 'project_type': projectType,
      if (displayName != null) 'display_name': displayName,
      if (typeSetAt != null) 'type_set_at': typeSetAt,
      if (isHidden != null) 'is_hidden': isHidden,
      if (groupId != null) 'group_id': groupId,
      if (vaultHubSlug != null) 'vault_hub_slug': vaultHubSlug,
      if (vaultLastSyncAt != null) 'vault_last_sync_at': vaultLastSyncAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectSettingsTableCompanion copyWith({
    Value<String>? folderId,
    Value<String?>? projectType,
    Value<String?>? displayName,
    Value<DateTime?>? typeSetAt,
    Value<bool>? isHidden,
    Value<String?>? groupId,
    Value<String?>? vaultHubSlug,
    Value<DateTime?>? vaultLastSyncAt,
    Value<int>? rowid,
  }) {
    return ProjectSettingsTableCompanion(
      folderId: folderId ?? this.folderId,
      projectType: projectType ?? this.projectType,
      displayName: displayName ?? this.displayName,
      typeSetAt: typeSetAt ?? this.typeSetAt,
      isHidden: isHidden ?? this.isHidden,
      groupId: groupId ?? this.groupId,
      vaultHubSlug: vaultHubSlug ?? this.vaultHubSlug,
      vaultLastSyncAt: vaultLastSyncAt ?? this.vaultLastSyncAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (projectType.present) {
      map['project_type'] = Variable<String>(projectType.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (typeSetAt.present) {
      map['type_set_at'] = Variable<DateTime>(typeSetAt.value);
    }
    if (isHidden.present) {
      map['is_hidden'] = Variable<bool>(isHidden.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (vaultHubSlug.present) {
      map['vault_hub_slug'] = Variable<String>(vaultHubSlug.value);
    }
    if (vaultLastSyncAt.present) {
      map['vault_last_sync_at'] = Variable<DateTime>(vaultLastSyncAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectSettingsTableCompanion(')
          ..write('folderId: $folderId, ')
          ..write('projectType: $projectType, ')
          ..write('displayName: $displayName, ')
          ..write('typeSetAt: $typeSetAt, ')
          ..write('isHidden: $isHidden, ')
          ..write('groupId: $groupId, ')
          ..write('vaultHubSlug: $vaultHubSlug, ')
          ..write('vaultLastSyncAt: $vaultLastSyncAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectGroupsTableTable extends ProjectGroupsTable
    with TableInfo<$ProjectGroupsTableTable, ProjectGroupsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectGroupsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isSystemMeta = const VerificationMeta(
    'isSystem',
  );
  @override
  late final GeneratedColumn<bool> isSystem = GeneratedColumn<bool>(
    'is_system',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_system" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, isSystem];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_groups_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectGroupsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_system')) {
      context.handle(
        _isSystemMeta,
        isSystem.isAcceptableOrUnknown(data['is_system']!, _isSystemMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectGroupsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectGroupsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isSystem: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_system'],
      )!,
    );
  }

  @override
  $ProjectGroupsTableTable createAlias(String alias) {
    return $ProjectGroupsTableTable(attachedDatabase, alias);
  }
}

class ProjectGroupsTableData extends DataClass
    implements Insertable<ProjectGroupsTableData> {
  final String id;
  final String name;
  final bool isSystem;
  const ProjectGroupsTableData({
    required this.id,
    required this.name,
    required this.isSystem,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['is_system'] = Variable<bool>(isSystem);
    return map;
  }

  ProjectGroupsTableCompanion toCompanion(bool nullToAbsent) {
    return ProjectGroupsTableCompanion(
      id: Value(id),
      name: Value(name),
      isSystem: Value(isSystem),
    );
  }

  factory ProjectGroupsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectGroupsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isSystem: serializer.fromJson<bool>(json['isSystem']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'isSystem': serializer.toJson<bool>(isSystem),
    };
  }

  ProjectGroupsTableData copyWith({String? id, String? name, bool? isSystem}) =>
      ProjectGroupsTableData(
        id: id ?? this.id,
        name: name ?? this.name,
        isSystem: isSystem ?? this.isSystem,
      );
  ProjectGroupsTableData copyWithCompanion(ProjectGroupsTableCompanion data) {
    return ProjectGroupsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isSystem: data.isSystem.present ? data.isSystem.value : this.isSystem,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectGroupsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isSystem: $isSystem')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, isSystem);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectGroupsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.isSystem == this.isSystem);
}

class ProjectGroupsTableCompanion
    extends UpdateCompanion<ProjectGroupsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> isSystem;
  final Value<int> rowid;
  const ProjectGroupsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isSystem = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectGroupsTableCompanion.insert({
    required String id,
    required String name,
    this.isSystem = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<ProjectGroupsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? isSystem,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isSystem != null) 'is_system': isSystem,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectGroupsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<bool>? isSystem,
    Value<int>? rowid,
  }) {
    return ProjectGroupsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isSystem: isSystem ?? this.isSystem,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isSystem.present) {
      map['is_system'] = Variable<bool>(isSystem.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectGroupsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isSystem: $isSystem, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupCollapseStateTableTable extends GroupCollapseStateTable
    with TableInfo<$GroupCollapseStateTableTable, GroupCollapseStateTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupCollapseStateTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _collapsedMeta = const VerificationMeta(
    'collapsed',
  );
  @override
  late final GeneratedColumn<bool> collapsed = GeneratedColumn<bool>(
    'collapsed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("collapsed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [groupId, collapsed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_collapse_state_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupCollapseStateTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('collapsed')) {
      context.handle(
        _collapsedMeta,
        collapsed.isAcceptableOrUnknown(data['collapsed']!, _collapsedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId};
  @override
  GroupCollapseStateTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupCollapseStateTableData(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      collapsed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}collapsed'],
      )!,
    );
  }

  @override
  $GroupCollapseStateTableTable createAlias(String alias) {
    return $GroupCollapseStateTableTable(attachedDatabase, alias);
  }
}

class GroupCollapseStateTableData extends DataClass
    implements Insertable<GroupCollapseStateTableData> {
  final String groupId;
  final bool collapsed;
  const GroupCollapseStateTableData({
    required this.groupId,
    required this.collapsed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['collapsed'] = Variable<bool>(collapsed);
    return map;
  }

  GroupCollapseStateTableCompanion toCompanion(bool nullToAbsent) {
    return GroupCollapseStateTableCompanion(
      groupId: Value(groupId),
      collapsed: Value(collapsed),
    );
  }

  factory GroupCollapseStateTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupCollapseStateTableData(
      groupId: serializer.fromJson<String>(json['groupId']),
      collapsed: serializer.fromJson<bool>(json['collapsed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'collapsed': serializer.toJson<bool>(collapsed),
    };
  }

  GroupCollapseStateTableData copyWith({String? groupId, bool? collapsed}) =>
      GroupCollapseStateTableData(
        groupId: groupId ?? this.groupId,
        collapsed: collapsed ?? this.collapsed,
      );
  GroupCollapseStateTableData copyWithCompanion(
    GroupCollapseStateTableCompanion data,
  ) {
    return GroupCollapseStateTableData(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      collapsed: data.collapsed.present ? data.collapsed.value : this.collapsed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupCollapseStateTableData(')
          ..write('groupId: $groupId, ')
          ..write('collapsed: $collapsed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(groupId, collapsed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupCollapseStateTableData &&
          other.groupId == this.groupId &&
          other.collapsed == this.collapsed);
}

class GroupCollapseStateTableCompanion
    extends UpdateCompanion<GroupCollapseStateTableData> {
  final Value<String> groupId;
  final Value<bool> collapsed;
  final Value<int> rowid;
  const GroupCollapseStateTableCompanion({
    this.groupId = const Value.absent(),
    this.collapsed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupCollapseStateTableCompanion.insert({
    required String groupId,
    this.collapsed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId);
  static Insertable<GroupCollapseStateTableData> custom({
    Expression<String>? groupId,
    Expression<bool>? collapsed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (collapsed != null) 'collapsed': collapsed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupCollapseStateTableCompanion copyWith({
    Value<String>? groupId,
    Value<bool>? collapsed,
    Value<int>? rowid,
  }) {
    return GroupCollapseStateTableCompanion(
      groupId: groupId ?? this.groupId,
      collapsed: collapsed ?? this.collapsed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (collapsed.present) {
      map['collapsed'] = Variable<bool>(collapsed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupCollapseStateTableCompanion(')
          ..write('groupId: $groupId, ')
          ..write('collapsed: $collapsed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppConfigTableTable appConfigTable = $AppConfigTableTable(this);
  late final $ProjectSettingsTableTable projectSettingsTable =
      $ProjectSettingsTableTable(this);
  late final $ProjectGroupsTableTable projectGroupsTable =
      $ProjectGroupsTableTable(this);
  late final $GroupCollapseStateTableTable groupCollapseStateTable =
      $GroupCollapseStateTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appConfigTable,
    projectSettingsTable,
    projectGroupsTable,
    groupCollapseStateTable,
  ];
}

typedef $$AppConfigTableTableCreateCompanionBuilder =
    AppConfigTableCompanion Function({
      Value<int> id,
      Value<String> scanDir,
      Value<String> ignoreListJson,
      Value<String> gitBinaryPath,
      Value<String> themeMode,
      Value<String> vaultDir,
      Value<String> viewMode,
      Value<bool> projectOrganizationSeedApplied,
      Value<String> vaultHubFolder,
    });
typedef $$AppConfigTableTableUpdateCompanionBuilder =
    AppConfigTableCompanion Function({
      Value<int> id,
      Value<String> scanDir,
      Value<String> ignoreListJson,
      Value<String> gitBinaryPath,
      Value<String> themeMode,
      Value<String> vaultDir,
      Value<String> viewMode,
      Value<bool> projectOrganizationSeedApplied,
      Value<String> vaultHubFolder,
    });

class $$AppConfigTableTableFilterComposer
    extends Composer<_$AppDatabase, $AppConfigTableTable> {
  $$AppConfigTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scanDir => $composableBuilder(
    column: $table.scanDir,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ignoreListJson => $composableBuilder(
    column: $table.ignoreListJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gitBinaryPath => $composableBuilder(
    column: $table.gitBinaryPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vaultDir => $composableBuilder(
    column: $table.vaultDir,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get viewMode => $composableBuilder(
    column: $table.viewMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get projectOrganizationSeedApplied => $composableBuilder(
    column: $table.projectOrganizationSeedApplied,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vaultHubFolder => $composableBuilder(
    column: $table.vaultHubFolder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppConfigTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AppConfigTableTable> {
  $$AppConfigTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scanDir => $composableBuilder(
    column: $table.scanDir,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ignoreListJson => $composableBuilder(
    column: $table.ignoreListJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gitBinaryPath => $composableBuilder(
    column: $table.gitBinaryPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vaultDir => $composableBuilder(
    column: $table.vaultDir,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get viewMode => $composableBuilder(
    column: $table.viewMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get projectOrganizationSeedApplied =>
      $composableBuilder(
        column: $table.projectOrganizationSeedApplied,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<String> get vaultHubFolder => $composableBuilder(
    column: $table.vaultHubFolder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppConfigTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppConfigTableTable> {
  $$AppConfigTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scanDir =>
      $composableBuilder(column: $table.scanDir, builder: (column) => column);

  GeneratedColumn<String> get ignoreListJson => $composableBuilder(
    column: $table.ignoreListJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gitBinaryPath => $composableBuilder(
    column: $table.gitBinaryPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get themeMode =>
      $composableBuilder(column: $table.themeMode, builder: (column) => column);

  GeneratedColumn<String> get vaultDir =>
      $composableBuilder(column: $table.vaultDir, builder: (column) => column);

  GeneratedColumn<String> get viewMode =>
      $composableBuilder(column: $table.viewMode, builder: (column) => column);

  GeneratedColumn<bool> get projectOrganizationSeedApplied =>
      $composableBuilder(
        column: $table.projectOrganizationSeedApplied,
        builder: (column) => column,
      );

  GeneratedColumn<String> get vaultHubFolder => $composableBuilder(
    column: $table.vaultHubFolder,
    builder: (column) => column,
  );
}

class $$AppConfigTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppConfigTableTable,
          AppConfigTableData,
          $$AppConfigTableTableFilterComposer,
          $$AppConfigTableTableOrderingComposer,
          $$AppConfigTableTableAnnotationComposer,
          $$AppConfigTableTableCreateCompanionBuilder,
          $$AppConfigTableTableUpdateCompanionBuilder,
          (
            AppConfigTableData,
            BaseReferences<
              _$AppDatabase,
              $AppConfigTableTable,
              AppConfigTableData
            >,
          ),
          AppConfigTableData,
          PrefetchHooks Function()
        > {
  $$AppConfigTableTableTableManager(
    _$AppDatabase db,
    $AppConfigTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppConfigTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppConfigTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppConfigTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> scanDir = const Value.absent(),
                Value<String> ignoreListJson = const Value.absent(),
                Value<String> gitBinaryPath = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
                Value<String> vaultDir = const Value.absent(),
                Value<String> viewMode = const Value.absent(),
                Value<bool> projectOrganizationSeedApplied =
                    const Value.absent(),
                Value<String> vaultHubFolder = const Value.absent(),
              }) => AppConfigTableCompanion(
                id: id,
                scanDir: scanDir,
                ignoreListJson: ignoreListJson,
                gitBinaryPath: gitBinaryPath,
                themeMode: themeMode,
                vaultDir: vaultDir,
                viewMode: viewMode,
                projectOrganizationSeedApplied: projectOrganizationSeedApplied,
                vaultHubFolder: vaultHubFolder,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> scanDir = const Value.absent(),
                Value<String> ignoreListJson = const Value.absent(),
                Value<String> gitBinaryPath = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
                Value<String> vaultDir = const Value.absent(),
                Value<String> viewMode = const Value.absent(),
                Value<bool> projectOrganizationSeedApplied =
                    const Value.absent(),
                Value<String> vaultHubFolder = const Value.absent(),
              }) => AppConfigTableCompanion.insert(
                id: id,
                scanDir: scanDir,
                ignoreListJson: ignoreListJson,
                gitBinaryPath: gitBinaryPath,
                themeMode: themeMode,
                vaultDir: vaultDir,
                viewMode: viewMode,
                projectOrganizationSeedApplied: projectOrganizationSeedApplied,
                vaultHubFolder: vaultHubFolder,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppConfigTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppConfigTableTable,
      AppConfigTableData,
      $$AppConfigTableTableFilterComposer,
      $$AppConfigTableTableOrderingComposer,
      $$AppConfigTableTableAnnotationComposer,
      $$AppConfigTableTableCreateCompanionBuilder,
      $$AppConfigTableTableUpdateCompanionBuilder,
      (
        AppConfigTableData,
        BaseReferences<_$AppDatabase, $AppConfigTableTable, AppConfigTableData>,
      ),
      AppConfigTableData,
      PrefetchHooks Function()
    >;
typedef $$ProjectSettingsTableTableCreateCompanionBuilder =
    ProjectSettingsTableCompanion Function({
      required String folderId,
      Value<String?> projectType,
      Value<String?> displayName,
      Value<DateTime?> typeSetAt,
      Value<bool> isHidden,
      Value<String?> groupId,
      Value<String?> vaultHubSlug,
      Value<DateTime?> vaultLastSyncAt,
      Value<int> rowid,
    });
typedef $$ProjectSettingsTableTableUpdateCompanionBuilder =
    ProjectSettingsTableCompanion Function({
      Value<String> folderId,
      Value<String?> projectType,
      Value<String?> displayName,
      Value<DateTime?> typeSetAt,
      Value<bool> isHidden,
      Value<String?> groupId,
      Value<String?> vaultHubSlug,
      Value<DateTime?> vaultLastSyncAt,
      Value<int> rowid,
    });

class $$ProjectSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectSettingsTableTable> {
  $$ProjectSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectType => $composableBuilder(
    column: $table.projectType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get typeSetAt => $composableBuilder(
    column: $table.typeSetAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vaultHubSlug => $composableBuilder(
    column: $table.vaultHubSlug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get vaultLastSyncAt => $composableBuilder(
    column: $table.vaultLastSyncAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectSettingsTableTable> {
  $$ProjectSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectType => $composableBuilder(
    column: $table.projectType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get typeSetAt => $composableBuilder(
    column: $table.typeSetAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vaultHubSlug => $composableBuilder(
    column: $table.vaultHubSlug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get vaultLastSyncAt => $composableBuilder(
    column: $table.vaultLastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectSettingsTableTable> {
  $$ProjectSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get projectType => $composableBuilder(
    column: $table.projectType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get typeSetAt =>
      $composableBuilder(column: $table.typeSetAt, builder: (column) => column);

  GeneratedColumn<bool> get isHidden =>
      $composableBuilder(column: $table.isHidden, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get vaultHubSlug => $composableBuilder(
    column: $table.vaultHubSlug,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get vaultLastSyncAt => $composableBuilder(
    column: $table.vaultLastSyncAt,
    builder: (column) => column,
  );
}

class $$ProjectSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectSettingsTableTable,
          ProjectSettingsTableData,
          $$ProjectSettingsTableTableFilterComposer,
          $$ProjectSettingsTableTableOrderingComposer,
          $$ProjectSettingsTableTableAnnotationComposer,
          $$ProjectSettingsTableTableCreateCompanionBuilder,
          $$ProjectSettingsTableTableUpdateCompanionBuilder,
          (
            ProjectSettingsTableData,
            BaseReferences<
              _$AppDatabase,
              $ProjectSettingsTableTable,
              ProjectSettingsTableData
            >,
          ),
          ProjectSettingsTableData,
          PrefetchHooks Function()
        > {
  $$ProjectSettingsTableTableTableManager(
    _$AppDatabase db,
    $ProjectSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProjectSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> folderId = const Value.absent(),
                Value<String?> projectType = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<DateTime?> typeSetAt = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> vaultHubSlug = const Value.absent(),
                Value<DateTime?> vaultLastSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectSettingsTableCompanion(
                folderId: folderId,
                projectType: projectType,
                displayName: displayName,
                typeSetAt: typeSetAt,
                isHidden: isHidden,
                groupId: groupId,
                vaultHubSlug: vaultHubSlug,
                vaultLastSyncAt: vaultLastSyncAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String folderId,
                Value<String?> projectType = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<DateTime?> typeSetAt = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> vaultHubSlug = const Value.absent(),
                Value<DateTime?> vaultLastSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectSettingsTableCompanion.insert(
                folderId: folderId,
                projectType: projectType,
                displayName: displayName,
                typeSetAt: typeSetAt,
                isHidden: isHidden,
                groupId: groupId,
                vaultHubSlug: vaultHubSlug,
                vaultLastSyncAt: vaultLastSyncAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectSettingsTableTable,
      ProjectSettingsTableData,
      $$ProjectSettingsTableTableFilterComposer,
      $$ProjectSettingsTableTableOrderingComposer,
      $$ProjectSettingsTableTableAnnotationComposer,
      $$ProjectSettingsTableTableCreateCompanionBuilder,
      $$ProjectSettingsTableTableUpdateCompanionBuilder,
      (
        ProjectSettingsTableData,
        BaseReferences<
          _$AppDatabase,
          $ProjectSettingsTableTable,
          ProjectSettingsTableData
        >,
      ),
      ProjectSettingsTableData,
      PrefetchHooks Function()
    >;
typedef $$ProjectGroupsTableTableCreateCompanionBuilder =
    ProjectGroupsTableCompanion Function({
      required String id,
      required String name,
      Value<bool> isSystem,
      Value<int> rowid,
    });
typedef $$ProjectGroupsTableTableUpdateCompanionBuilder =
    ProjectGroupsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<bool> isSystem,
      Value<int> rowid,
    });

class $$ProjectGroupsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectGroupsTableTable> {
  $$ProjectGroupsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSystem => $composableBuilder(
    column: $table.isSystem,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectGroupsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectGroupsTableTable> {
  $$ProjectGroupsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSystem => $composableBuilder(
    column: $table.isSystem,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectGroupsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectGroupsTableTable> {
  $$ProjectGroupsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isSystem =>
      $composableBuilder(column: $table.isSystem, builder: (column) => column);
}

class $$ProjectGroupsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectGroupsTableTable,
          ProjectGroupsTableData,
          $$ProjectGroupsTableTableFilterComposer,
          $$ProjectGroupsTableTableOrderingComposer,
          $$ProjectGroupsTableTableAnnotationComposer,
          $$ProjectGroupsTableTableCreateCompanionBuilder,
          $$ProjectGroupsTableTableUpdateCompanionBuilder,
          (
            ProjectGroupsTableData,
            BaseReferences<
              _$AppDatabase,
              $ProjectGroupsTableTable,
              ProjectGroupsTableData
            >,
          ),
          ProjectGroupsTableData,
          PrefetchHooks Function()
        > {
  $$ProjectGroupsTableTableTableManager(
    _$AppDatabase db,
    $ProjectGroupsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectGroupsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectGroupsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectGroupsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isSystem = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectGroupsTableCompanion(
                id: id,
                name: name,
                isSystem: isSystem,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<bool> isSystem = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectGroupsTableCompanion.insert(
                id: id,
                name: name,
                isSystem: isSystem,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectGroupsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectGroupsTableTable,
      ProjectGroupsTableData,
      $$ProjectGroupsTableTableFilterComposer,
      $$ProjectGroupsTableTableOrderingComposer,
      $$ProjectGroupsTableTableAnnotationComposer,
      $$ProjectGroupsTableTableCreateCompanionBuilder,
      $$ProjectGroupsTableTableUpdateCompanionBuilder,
      (
        ProjectGroupsTableData,
        BaseReferences<
          _$AppDatabase,
          $ProjectGroupsTableTable,
          ProjectGroupsTableData
        >,
      ),
      ProjectGroupsTableData,
      PrefetchHooks Function()
    >;
typedef $$GroupCollapseStateTableTableCreateCompanionBuilder =
    GroupCollapseStateTableCompanion Function({
      required String groupId,
      Value<bool> collapsed,
      Value<int> rowid,
    });
typedef $$GroupCollapseStateTableTableUpdateCompanionBuilder =
    GroupCollapseStateTableCompanion Function({
      Value<String> groupId,
      Value<bool> collapsed,
      Value<int> rowid,
    });

class $$GroupCollapseStateTableTableFilterComposer
    extends Composer<_$AppDatabase, $GroupCollapseStateTableTable> {
  $$GroupCollapseStateTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get collapsed => $composableBuilder(
    column: $table.collapsed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupCollapseStateTableTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupCollapseStateTableTable> {
  $$GroupCollapseStateTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get collapsed => $composableBuilder(
    column: $table.collapsed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupCollapseStateTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupCollapseStateTableTable> {
  $$GroupCollapseStateTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<bool> get collapsed =>
      $composableBuilder(column: $table.collapsed, builder: (column) => column);
}

class $$GroupCollapseStateTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupCollapseStateTableTable,
          GroupCollapseStateTableData,
          $$GroupCollapseStateTableTableFilterComposer,
          $$GroupCollapseStateTableTableOrderingComposer,
          $$GroupCollapseStateTableTableAnnotationComposer,
          $$GroupCollapseStateTableTableCreateCompanionBuilder,
          $$GroupCollapseStateTableTableUpdateCompanionBuilder,
          (
            GroupCollapseStateTableData,
            BaseReferences<
              _$AppDatabase,
              $GroupCollapseStateTableTable,
              GroupCollapseStateTableData
            >,
          ),
          GroupCollapseStateTableData,
          PrefetchHooks Function()
        > {
  $$GroupCollapseStateTableTableTableManager(
    _$AppDatabase db,
    $GroupCollapseStateTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupCollapseStateTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$GroupCollapseStateTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$GroupCollapseStateTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<bool> collapsed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupCollapseStateTableCompanion(
                groupId: groupId,
                collapsed: collapsed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                Value<bool> collapsed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupCollapseStateTableCompanion.insert(
                groupId: groupId,
                collapsed: collapsed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupCollapseStateTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupCollapseStateTableTable,
      GroupCollapseStateTableData,
      $$GroupCollapseStateTableTableFilterComposer,
      $$GroupCollapseStateTableTableOrderingComposer,
      $$GroupCollapseStateTableTableAnnotationComposer,
      $$GroupCollapseStateTableTableCreateCompanionBuilder,
      $$GroupCollapseStateTableTableUpdateCompanionBuilder,
      (
        GroupCollapseStateTableData,
        BaseReferences<
          _$AppDatabase,
          $GroupCollapseStateTableTable,
          GroupCollapseStateTableData
        >,
      ),
      GroupCollapseStateTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppConfigTableTableTableManager get appConfigTable =>
      $$AppConfigTableTableTableManager(_db, _db.appConfigTable);
  $$ProjectSettingsTableTableTableManager get projectSettingsTable =>
      $$ProjectSettingsTableTableTableManager(_db, _db.projectSettingsTable);
  $$ProjectGroupsTableTableTableManager get projectGroupsTable =>
      $$ProjectGroupsTableTableTableManager(_db, _db.projectGroupsTable);
  $$GroupCollapseStateTableTableTableManager get groupCollapseStateTable =>
      $$GroupCollapseStateTableTableTableManager(
        _db,
        _db.groupCollapseStateTable,
      );
}
