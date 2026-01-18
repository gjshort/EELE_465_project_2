# EELE 465 Project 2

In this project, you'll bit-bang i2c and communicate with a real-time clock.

## Repository organization

- :file_folder: [docs](docs) &mdash; Documentation
- :file_folder: [src](src) &mdash; Source code
- :page_facing_up: [lnk_msp430fr2355.cmd](lnk_msp430fr2355.cmd) &mdash; Linker options file
- :page_facing_up: [.cproject](.cproject) &mdash; Eclipse Theia project settings
- :page_facing_up: [.ccsproject](.cssproject) &mdash; CCS-specific project settings
- :page_facing_up: [.project](.project) &mdash; Eclipse Theia project settings
- :file_folder: [.settings](.settings) &mdash; Eclipse Theia settings
- :page_facing_up: [.gitignore](.gitignore) &mdash; [gitignore files](https://git-scm.com/docs/gitignorehttps://git-scm.com/docs/gitignore) specify files and folders that git should ignore / not track.

## CCS project setup

This repository already contains a CCS project, thus you just need to import the project into CCS.


1. Clone this repo somewhere. I might suggest something like `<class_folder>/projects/`.
2. Open CCS *without* an active workspace. If there is an active workspace, you will need to launch a new window of CCS.
3. Import the project / add it to the workspace. There are two ways to do this:
    1. Add the folder to the workspace
        1. *File -> Add Folder to Workspace...* or right-click in an empty portion of the workspace section in the explorer sidebar and click *Add Folder to Workspace...*
    2. Import the project
        1. *File -> Import Projects*
        2. Select this repo's directory
        3. Set "Import destination..." as "Import projects at their original location". This will keep your repository in the location you cloned it, rather than copying it to some workspace folder.
4. Assuming everything works, CCS should now recognize your project. I suggest you save your workspace as a `.theia-workspace` file: *File -> Save Workspace As...* You can save the workspace file wherever you'd like, but I suggest keeping it somewhere in your `<class_folder>`. You can add future projects to the same workspace file by following the steps above.

> [!WARNING]
> I'm using CCS 20.4.0, thus that's what the project was created in and for.  If you choose to use an older version of CCS, you will need to delete all the project files and folders listed in the [Repository organization](#repository-organization) section, then create a new project inside this repo's folder.
