;;; peut-gerer -- Peut-gerer Enables Users To... manage project workflows

;; Copyright (C) 2020 Matt Trzcinski (excalamus AT tutanota DOT com)

;; This file is not part of GNU Emacs.

;; Author: Matt Trzcinski
;; Version: 0.99.0
;; Package-Requires: ((emacs "26.3"))
;; Keywords:  project, management, shell
;; URL: https://github.com/excalamus/peut-gerer

;; This is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 3, or (at your option) any later
;; version.
;;
;; This is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
;; for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
;; MA 02110-1301 USA.

;;; Commentary:

;; `peut-gerer' is a package to manage project workflows.  It is
;; currently developed to manage a particular Python workflow,
;; although it could be easily modified to support other kinds.

;; A project is a collection of files dedicated toward a common
;; purpose (e.g. an application written in Python).  Each project
;; lives in a root directory, has an entry point, and a corresponding
;; shell process.  A project may have associated environments
;; (e.g. venv, .git, etc.) or commands to run in the shell.

;; The project workflow operates by sending commands to a shell which
;; has appropriate environment variables set.

;; `peut-gerer' provides tools to manage concurrent project workflows:

;; activate project:   use alist entry to set up shell and commands
;; deactivate project: close associated buffers and processes
;; select project:     act according to a particular project

;; Project details are kept in the `peut-gerer-project-alist', an alist of
;; plists (See 'C-h i d m Elisp <RET> m Lists <RET>' for more
;; details):

;;     (setq peut-gerer-project-alist
;;           '(("project-x"
;;              :root "/data/data/com.termux/files/home/projects/project-x/"
;;              :main "main.py"
;;              :venv  "/data/data/com.termux/files/home/projects/project-x/venv/"
;;              :activate "/data/data/com.termux/files/home/projects/project-x/venv/bin/activate"
;;              :commands ("pyinstaller build.spec")
;;              )
;;             ("project-a"
;;              :root "C:\\projects\\project-umbrella\\apps\\project_a\\"
;;              :main "project_a.py"
;;              :venv "C:\\Users\\excalamus\\Anaconda3\\envs\\project_a\\"
;;              :activate "C:\\Users\\excalamus\\Anaconda3\\condabin\\conda.bat activate"
;;              )))

;; The ':commands' keyword takes a list of strings.  These will be
;; loaded into the `peut-gerer-send-command' history.  Press <down> or C-n when
;; calling `peut-gerer-send-command' interactively to access these commands.

;; Once the `peut-gerer-project-alist' has been loaded, activate a project with
;; `peut-gerer-activate-project'.  Actions to perform after activation, such as
;; activating pyvenv-mode, can be done with
;; `peut-gerer-after-activate-functions'.  See the docstring for more details.

;;    (setq peut-gerer-after-activate-functions '(pyvenv-activate))

;; Interact with the project shell using `peut-gerer-send-command' and
;; `peut-gerer-buffer-file-to-shell'.  Toggle between projects with
;; `peut-gerer-select-project' and finish with `peut-gerer-deactivate-project'.  Check the
;; docstrings for details.

;;; Code:


;;; Requirements:
;; None!


;;; Variables:

(defvar peut-gerer-current-project nil
  "Name of the primary active project.")

(defvar peut-gerer-command-prefix "python"
  "Prefix to be used in shell calls.

This is typically an executable such as \"python\".")

(defvar peut-gerer-shell "*shell*"
  "Primary shell process buffer.")

(defvar peut-gerer-root default-directory
  "Active project's root directory.")

(defvar peut-gerer-command ""
  "Primary shell command.

This can be any string.  Several commands, such as
`peut-gerer-set-command-to-current-file',
`peut-gerer-activate-project', and `peut-gerer-select-project',
set this using the `peut-gerer-command-prefix' by postfixing
option flags or file paths.  Use `peut-gerer-set-command' to set
manually.")

;; todo generalize, currently used just to call `pyvenv-activate'
(defvar peut-gerer-after-activate-functions nil
  "Functions to run at the end of `peut-gerer-activate-project'.

Functions must accept a path to a virtual environment.")

;; todo generalize, currently used just to call `pyvenv-activate'
(defvar peut-gerer-after-select-functions nil
  "Functions to run at the end of `peut-gerer-activate-project'.

Functions must accept a path to a virtual environment.")

;; todo projects are currently python centric; perhaps generalize with
;; a :type keyword which triggers the appropriate activation sequence
;; for the type (python, C, etc.)
(defvar peut-gerer-project-alist nil
  "Project alist.

An entry in the `peut-gerer-project-alist' must contain a :root,
:main, :venv, and :activate.  For best results, use absolute
paths.

:root     -- project root directory
:main     -- entry point
:venv     -- virtual environment directory
:activate -- activation command
:commands -- commands to add to `peut-gerer-send-command' history

Example:

    (setq peut-gerer-project-alist
        '((\"project-x\"
            :root \"/data/data/com.termux/files/home/projects/project-x/\"
            :main \"main.py\"
            :venv  \"/data/data/com.termux/files/home/projects/project-x/venv/\"
            :activate \"source /data/data/com.termux/files/home/projects/project-x/venv/bin/activate\"
            :commands (\"pyinstaller build.spec\")
            )
            (\"project-a\"
            :root \"C:\\projects\\project-umbrella\\apps\\project_a\\\"
            :main \"project_a.py\"
            :venv \"C:\\Users\\excalamus\\Anaconda3\\envs\\project_a\\\"
            :activate \"C:\\Users\\excalamus\\Anaconda3\\condabin\\conda.bat activate\"
            )))")

(defvar peut-gerer--active-projects-alist nil
  "Active projects.")

(defvar peut-gerer--command-history nil
  "Command history for `peut-gerer-send-command'

Modified by `peut-gerer-activate-project' and
`peut-gerer-select-project' with the commands listed in the
`peut-gerer-project-alist' ':commands' keyword.")


;;; Functions:

(defun peut-gerer-set-command-prefix (prefix)
  "Set `peut-gerer-command-prefix' to PREFIX.

PREFIX may be any string.  This is prepended to the default
`peut-gerer-command' and is typically a shell
command/binary (e.g. \"python\").  The
`peut-gerer-command-prefix' is used to modify
`peut-gerer-command' by functions like
`peut-gerer-set-command-to-current-file'."
  (interactive
   (list (read-string "Set command prefix: " "python" nil "python")))
  (setq peut-gerer-command-prefix prefix)
  (message "Set `peut-gerer-command-prefix' to %s" peut-gerer-command-prefix))

(defun peut-gerer-set-shell (pbuff)
  "Set `peut-gerer-shell' to the buffer name PBUFF associated with a process.

For example, if 'shell' is a process, PBUFF is the buffer name
\"*shell*\" associated with it."
  (interactive
   (list (read-buffer "Set shell to: " nil t '(lambda (x) (processp (get-buffer-process (car x)))))))
  (setq peut-gerer-shell pbuff)
  (message "Set `peut-gerer-shell' to: %s" peut-gerer-shell))

(defun peut-gerer-set-command (new-command)
  "Set `peut-gerer-command' to NEW-COMMAND.

NEW-COMMAND can be any string."
  (interactive "sShell command: ")
  (setq peut-gerer-command new-command))

(defun peut-gerer-set-command-to-current-file ()
  "Postfix current buffer file to `peut-gerer-command-prefix'.

This is useful if, for instance, a project was started using one
file, but later in development another file needs to be called
frequently.  It is like a permanent version of
`peut-gerer-buffer-file-to-shell'."
  (interactive)
  (setq peut-gerer-command (concat peut-gerer-command-prefix " "
				   (format "\"%s\"" (buffer-file-name))))
  (message "Set `peut-gerer-command' to \"%s\"" peut-gerer-command))

(defun peut-gerer-create-shell (name)
    "Create shell with a given NAME.

NAME should have earmuffs (e.g. *NAME*) if it is to follow Emacs
naming conventions.  Earmuffs indicate that the buffer is special
use and not associated with a file.

Returns newly created shell process.

Adapted from URL `https://stackoverflow.com/a/36450889/5065796'"
    (interactive
     (let ((name (read-string "Create shell name: " nil)))
       (list name)))
    (let ((name (or name peut-gerer-shell)))
      (get-buffer-process (shell name))))

(defun peut-gerer-switch-to (target &optional raise all-frames)
  "Switch to TARGET buffer and RAISE.

TARGET may be a buffer, buffer name, or symbol.  Symbol may be
`:main' or `:shell' and correspond to those in
`peut-gerer-project-alist'.

Switch to previous buffer if current buffer is TARGET.  When RAISE
is t, switch current window to TARGET.  See `get-buffer-window'
for ALL-FRAME options; default is `t'.  When RAISE is nil, goto
TARGET buffer only if it is visible."
  (interactive
   (let ((target (read-buffer "Switch to: " nil t)))
     (list target nil nil)))
  (let* ((target  ;; buffer name as string
          (cond ((eq target :shell) peut-gerer-shell)
                ((eq target :main) (buffer-name
                                    (get-file-buffer
                                     (plist-get (cdr (assoc peut-gerer-current-project
                                                            peut-gerer-project-alist)) :main))))
                ((bufferp target) (buffer-name target))
                ((stringp target) (if (get-buffer target) target
                                    (error "Invalid buffer %s" target)))

                (t (error "Invalid buffer %s" target))))
         (raise (or raise nil))
         (all-frames (or all-frames t)))
    (cond
     ((string-equal (buffer-name (current-buffer)) target)
      (switch-to-prev-buffer))
     ((get-buffer-window target all-frames)
      (progn
        (switch-to-buffer-other-frame target)
        (goto-char (point-max))))
     ((get-buffer target)
      (if raise
          (progn
            (switch-to-buffer target)
            (goto-char (point-max)))
        (message "Raising is disabled and %s is not currently visible!" target)))
     ((message "No %s buffer exists!" target)))))

(defun peut-gerer-send-command (command &optional pbuff beg end)
  "Send COMMAND to shell process with buffer name PBUFF.

PBUFF is the buffer name string of a process.  If the process
associated with PBUFF does not exist, it is created.  PBUFF is
then opened in the other window and control is returned to the
calling buffer.

See URL `https://stackoverflow.com/a/7053298/5065796'"
  (interactive
   (let* ((prompt (format "Send to %s: " peut-gerer-shell))
          (cmd (read-string prompt "" 'peut-gerer--command-history peut-gerer-command)))
   (list cmd peut-gerer-shell)))
  (let* ((pbuff (or pbuff peut-gerer-shell))
         (proc (or (get-buffer-process pbuff)
                   ;; create new process
                   (let ((currbuff (current-buffer))
                         (new-proc (peut-gerer-create-shell pbuff)))  ; creates a buried pbuff
                     (switch-to-buffer-other-window pbuff)
                     (switch-to-buffer currbuff)
                     new-proc)))
         (command-and-go (concat command "\n")))
    (with-current-buffer pbuff
      (goto-char (process-mark proc))
      (insert command-and-go)
      (move-marker (process-mark proc) (point)))
    (process-send-string proc command-and-go)
    (with-current-buffer pbuff
      (comint-add-to-input-history command))))

(defun peut-gerer-buffer-file-to-shell ()
  "Send current buffer file to shell as temporary postfix to `peut-gerer-command-prefix'."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (peut-gerer-send-command (concat peut-gerer-command-prefix " " file))
      (error "Command not sent. Buffer not visiting file"))))

(defun peut-gerer-send-region (&optional beg end pbuff)
  "Send region defined by BEG and END to shell process buffer PBUFF.

Use current region if BEG and END not provided.  Default PBUFF is
`peut-gerer-shell'."
  (interactive (if (use-region-p)
                   (list (region-beginning) (region-end) nil)
                 (list nil nil nil)))
  (let* ((beg (or beg (if (use-region-p) (region-beginning)) nil))
         (end (or end (if (use-region-p) (region-end)) nil))
         (substr (or (and beg end (buffer-substring-no-properties beg end)) nil))
         (pbuff (or pbuff peut-gerer-shell)))
    (if substr
        (peut-gerer-send-command substr pbuff)
      (error "No region selected"))))

(defun peut-gerer-open-dir (dirname &optional type)
  "Open all files with EXTENSION in DIRNAME.

Optional regex TYPE to open.

See URL `https://emacs.stackexchange.com/a/46480/15177'"
  (interactive "DOpen files in: ")
  (let ((type (or type "\\.py$"))
        (dirname (or dirname peut-gerer-root)))
    (mapc #'find-file (directory-files dirname t type nil))))

(defun peut-gerer-open-dir-recursive (dirname &optional ext)
  "Open all files in DIRNAME with EXT extension.  Default EXT is '.py'.

See URL `https://emacs.stackexchange.com/a/46480'"
  (interactive "DRecursively open dir: ")
  (unless ext (setq ext "py"))
  (let ((regexp (concat "\\." ext "$")))
    (mapc #'find-file (directory-files-recursively dirname regexp nil))))

(defun peut-gerer-kill-all-visiting-buffers (&optional dir)
  "Kill all buffers visiting DIR.

Default DIR is `peut-gerer-root'"
  (interactive)
  (let ((dir (or dir peut-gerer-root)))
    (mapcar
     (lambda (buf)
       (let ((bfn (buffer-file-name buf)))
         (and (not (null bfn))
              (string-match-p (regexp-quote dir) (file-name-directory bfn))
              (kill-buffer buf))))
     (buffer-list))))

;; todo make deactivation 'safe' so that other commands correctly
;; handle the case where no projects are active; select-project,
;; send-command*, deactivate project
(defun peut-gerer-deactivate-project (project)
  "Deactivate PROJECT.

Save all buffers before killing all buffers in `peut-gerer-root'
and removing PROJECT from `peut-gerer--active-projects-alist'."
  (interactive
   (list (completing-read "Deactivate project: " peut-gerer--active-projects-alist nil t "" nil)))
  (let* ((root (plist-get (cdr (assoc project peut-gerer-project-alist)) :root))
         (shell (concat "*" project "*"))
         (venv (plist-get (cdr (assoc project peut-gerer-project-alist)) :venv))
         ;; silence prompts
         (kill-buffer-query-functions nil))

    ;; todo save only those in root
    (save-some-buffers t)
    ;; todo make these not complain if buffers not found
    (peut-gerer-kill-all-visiting-buffers root)
    (kill-buffer shell)  ; and process

    (if (string-equal project peut-gerer-current-project)
        (progn
          (setq peut-gerer-current-project nil)
          (setq peut-gerer-shell nil)
          (setq peut-gerer-command nil)))

    (delete project peut-gerer--active-projects-alist)

    (message "Project '%s' deactivated" project)))

(defun peut-gerer-activate-project (project)
  "Set up environment for PROJECT."
  (interactive
   (list (completing-read "Activate project: " (mapcar 'car peut-gerer-project-alist) nil t nil nil)))
  (let* ((root (plist-get (cdr (assoc project peut-gerer-project-alist)) :root))
         (shell (concat "*" project "*"))
         (proc (peut-gerer-create-shell shell))
         (main (plist-get (cdr (assoc project peut-gerer-project-alist)) :main))
         (main-abs (if (not (file-name-absolute-p main))
                       (concat root main)
                     main))
         (venv (plist-get (cdr (assoc project peut-gerer-project-alist)) :venv))
         (activate (plist-get (cdr (assoc project peut-gerer-project-alist)) :activate))
         (activate-cmd activate)
         (commands (plist-get (cdr (assoc project peut-gerer-project-alist)) :commands)))

    ;; set up globals
    (setq peut-gerer-current-project project)
    (setq peut-gerer-root (subst-char-in-string ?\\ ?/ peut-gerer-root))
    (setq peut-gerer-shell shell)
    (setq peut-gerer-command-prefix "python")
    (setq peut-gerer-command (concat peut-gerer-command-prefix " " main-abs))

    ;; insert commands into peut-gerer--command-history
    (setq peut-gerer--command-history nil)
    (mapc #'(lambda (x) (add-to-history 'peut-gerer--command-history x)) commands)

    ;; set up shell
    (peut-gerer-send-command (concat "cd " root) shell)
    (peut-gerer-send-command activate-cmd shell)
    (with-current-buffer shell
      (comint-clear-buffer))

    ;; set up frame
    (delete-other-windows)
    (split-window-horizontally)
    (find-file main-abs)

    ;; activate virtual environment
    (run-hook-with-args 'peut-gerer-after-activate-functions venv)

    (add-to-list 'peut-gerer--active-projects-alist project)
    (message "Project '%s' loaded" project)))

(defun peut-gerer-select-project (project)
  "Toggle active PROJECT as current."
  (interactive
   (list (completing-read "Select project: " peut-gerer--active-projects-alist nil t "" nil)))
  (let* ((root (plist-get (cdr (assoc project peut-gerer-project-alist)) :root))
         (shell (concat "*" project "*"))
         (venv (plist-get (cdr (assoc project peut-gerer-project-alist)) :venv))
         (main (plist-get (cdr (assoc project peut-gerer-project-alist)) :main))
         (main-abs (if (not (file-name-absolute-p main))
                       (concat root main)
                     main))
         (commands (plist-get (cdr (assoc project peut-gerer-project-alist)) :commands)))

    (if (not (string-equal project peut-gerer-current-project))
        (progn
          (setq peut-gerer-root (subst-char-in-string ?\\ ?/ peut-gerer-root))
          (setq peut-gerer-shell shell)
          (setq peut-gerer-command-prefix "python")
          (setq peut-gerer-command (concat peut-gerer-command-prefix " " main-abs))

          ;; handle virtual environment
          (run-hook-with-args 'peut-gerer-after-select-functions venv)

          ;; insert commands into peut-gerer--command-history
          (setq peut-gerer--command-history nil)
          (mapc #'(lambda (x) (add-to-history 'peut-gerer--command-history x)) commands)
          (setq peut-gerer-current-project project)
          (message "Selected '%s' project" peut-gerer-current-project))
      (message "Project '%s' already current" peut-gerer-current-project))))

(provide 'peut-gerer)

;;; peut-gerer ends here
